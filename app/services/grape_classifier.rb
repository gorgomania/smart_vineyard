# app/services/grape_classifier.rb
require "onnxruntime"
require "vips"
require "json"
require "numo/narray"

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
    end
  end

  def initialize
    model_path = Rails.root.join("app/models/onnx/grape_model.onnx")

    unless File.exist?(model_path)
      raise "Model file not found at #{model_path}"
    end

    @session = OnnxRuntime::InferenceSession.new(model_path.to_s)
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
    image = Vips::Image.new_from_file(image_path)

    # Ресайз и центрирование
    scale = IMAGE_SIZE.to_f / [ image.width, image.height ].min
    resized_width = (image.width * scale).round
    resized_height = (image.height * scale).round
    resized = image.resize(scale)

    # Затем вырезаем центр
    crop_x = (resized_width - IMAGE_SIZE) / 2
    crop_y = (resized_height - IMAGE_SIZE) / 2
    cropped = resized.crop(crop_x, crop_y, IMAGE_SIZE, IMAGE_SIZE)

    # Приводим к RGB и 8-бит
    cropped = cropped.colourspace(:srgb)
    cropped = cropped.cast(:uchar)

    # Получаем пиксели
    pixels = cropped.to_a

    # Нормализация
    tensor_data = []

    3.times do |c|
      channel = []

      IMAGE_SIZE.times do |h|
        IMAGE_SIZE.times do |w|
          if pixels[h][w].nil? || pixels[h][w][c].nil?
            normalized = (128.0 / 255.0 - MEAN[c]) / STD[c]
          else
            normalized = (pixels[h][w][c].to_f / 255.0 - MEAN[c]) / STD[c]
          end
          channel << normalized
        end
      end

      tensor_data << channel
    end

    # Создаем тензор
    tensor = Numo::SFloat.cast(tensor_data).reshape(1, 3, IMAGE_SIZE, IMAGE_SIZE)

    tensor
  end

  def softmax(x)
    exp_x = x.map { |val| Math.exp(val - x.max) }
    sum_exp = exp_x.sum
    exp_x.map { |val| val / sum_exp }
  end
end
