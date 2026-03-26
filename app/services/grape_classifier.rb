# app/services/grape_classifier.rb
require "onnxruntime"
require "mini_magick"
require "json"
require "numo/narray"
require "tempfile"

class GrapeClassifier
  IMAGE_SIZE = 224
  MEAN = [ 0.485, 0.456, 0.406 ]
  STD = [ 0.229, 0.224, 0.225 ]

  class << self
    def predict_from_media_item(media_item)
      @instance ||= new

      unless media_item.media.attached?
        raise ArgumentError, "Media item has no attached file"
      end

      unless media_item.media.content_type.start_with?("image/")
        raise ArgumentError, "Attached file is not an image"
      end

      @instance.predict_from_active_storage(media_item.media)
    end

    def predict_from_file(file_path)
      @instance ||= new
      @instance.predict_from_path(file_path)
    end

    def class_names
      @class_names ||= JSON.parse(
        File.read(Rails.root.join("app/models/onnx/class_names.json"))
      )
    rescue
      [ "Сорт 1", "Сорт 2", "Сорт 3" ]
    end
  end

  def initialize
    model_path = Rails.root.join("app/models/onnx/grape_model.onnx")

    unless File.exist?(model_path)
      raise "Model file not found at #{model_path}"
    end

    @session = OnnxRuntime::InferenceSession.new(model_path.to_s)

    # Выводим информацию о модели
    puts "=" * 80
    puts "Model loaded successfully"
    puts "Inputs: #{@session.inputs}"
    puts "Outputs: #{@session.outputs}"
    puts "=" * 80
  end

  def predict_from_active_storage(attachment)
    attachment.blob.open(tmpdir: Rails.root.join("tmp")) do |tempfile|
      predict_from_path(tempfile.path)
    end
  end

  def predict_from_path(image_path)
    tensor = preprocess_image_from_path(image_path)

    # Используем жёстко заданные имена, как в ваших логах
    input_name   = "input"
    output_names = [ "output" ]

    # Лог для проверки
    Rails.logger.info "Using input: #{input_name}, outputs: #{output_names}"

    # Правильный вызов ONNX
    result = @session.run(output_names, { input_name => tensor })

    # Берём первый выход
    output = result[0]
    probabilities = softmax(output.to_a.flatten)

    top_predictions = probabilities
      .each_with_index
      .sort_by { |prob, _| -prob }
      .first(3)
      .map { |prob, idx| { class: self.class.class_names[idx], probability: prob, class_id: idx } }

    {
      predictions: top_predictions,
      top_class: top_predictions.first[:class],
      confidence: top_predictions.first[:probability],
      class_id: top_predictions.first[:class_id]
    }
  end
  private

  def preprocess_image_from_path(image_path)
    Rails.logger.info "Loading image: #{image_path}"

    image = MiniMagick::Image.open(image_path)
    Rails.logger.info "Original image: #{image.width}x#{image.height}"

    # Ресайз и центрирование
    image.combine_options do |cmd|
      cmd.resize "#{IMAGE_SIZE}x#{IMAGE_SIZE}^"
      cmd.gravity "center"
      cmd.extent "#{IMAGE_SIZE}x#{IMAGE_SIZE}"
    end

    # Принудительно конвертируем в RGB
    image.colorspace "sRGB"

    # Получаем пиксели
    pixels = image.get_pixels

    Rails.logger.info "Pixels structure: #{pixels.size}x#{pixels.first&.size}x#{pixels.first&.first&.size}"

    # Конвертируем градации серого в RGB
    processed_pixels = []

    IMAGE_SIZE.times do |h|
      row = []
      IMAGE_SIZE.times do |w|
        pixel = pixels[h][w]

        if pixel.is_a?(Array)
          if pixel.size == 1
            # Градации серого
            gray_value = pixel[0]
            row << [ gray_value, gray_value, gray_value ]
          elsif pixel.size >= 3
            # RGB или RGBA - берем первые 3 канала
            row << pixel[0..2]
          else
            # Неожиданный формат
            row << [ pixel[0], pixel[0], pixel[0] ]
          end
        else
          # Числовое значение
          gray_value = pixel
          row << [ gray_value, gray_value, gray_value ]
        end
      end
      processed_pixels << row
    end

    # Нормализация
    tensor_data = []

    3.times do |c|
      channel = []

      IMAGE_SIZE.times do |h|
        IMAGE_SIZE.times do |w|
          pixel_value = processed_pixels[h][w][c]

          if pixel_value.nil?
            raise "No channel #{c} at pixel (#{h}, #{w})"
          end

          normalized = (pixel_value.to_f / 255.0 - MEAN[c]) / STD[c]
          channel << normalized
        end
      end

      tensor_data << channel
    end

    # Создаем тензор
    tensor = Numo::SFloat.cast(tensor_data).reshape(1, 3, IMAGE_SIZE, IMAGE_SIZE)

    Rails.logger.info "Tensor created: shape=#{tensor.shape}, min=#{tensor.min}, max=#{tensor.max}"

    tensor
  end

  def softmax(x)
    exp_x = x.map { |val| Math.exp(val - x.max) }
    sum_exp = exp_x.sum
    exp_x.map { |val| val / sum_exp }
  end
end
