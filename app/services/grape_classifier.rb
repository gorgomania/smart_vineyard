# app/services/grape_classifier.rb
require "onnxruntime"
require "vips"
require "json"
class GrapeClassifier
  IMAGE_SIZE = 224
  MEAN = [ 0.485, 0.456, 0.406 ]
  STD = [ 0.229, 0.224, 0.225 ]
  # (val / 255 - mean) / std  =  val * NORM_SCALE + NORM_OFFSET
  NORM_SCALE = STD.map { |s| 1.0 / (255.0 * s) }.freeze
  NORM_OFFSET = MEAN.zip(STD).map { |m, s| -m / s }.freeze
  MUTEX = Mutex.new

  class << self
    def instance
      return @instance if @instance
      MUTEX.synchronize do
        @instance ||= new
      end
    end

    def predict_from_media_item(media_item)
      unless media_item.media.attached?
        raise ArgumentError, "Media item has no attached file"
      end

      unless media_item.media.content_type.start_with?("image/")
        raise ArgumentError, "Attached file is not an image"
      end

      instance.predict_from_active_storage(media_item.media)
    end

    def predict_from_file(file_path)
      instance.predict_from_path(file_path)
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

    # Один поток на инференс: параллельность дают процессы worker'а (JOB_CONCURRENCY),
    # иначе каждая сессия занимает все ядра и процессы мешают друг другу
    @session = OnnxRuntime::InferenceSession.new(model_path.to_s, intra_op_num_threads: 1, inter_op_num_threads: 1)
  end

  def predict_from_active_storage(attachment)
    BlobPath.open(attachment.blob, tmpdir: Rails.root.join("tmp")) do |path|
      predict_from_path(path)
    end
  end

  def predict_from_path(image_path)
    tensor = preprocess_image_from_path(image_path)

    # Используем жёстко заданные имена
    input_name   = "input"
    output_names = [ "output" ]

    # Вызов ONNX
    result = @session.run(output_names, { input_name => tensor })

    # Берём первый выход
    output = result[0]
    probabilities = softmax(output.to_a.flatten)

    top_predictions = probabilities
      .each_with_index
      .sort_by { |prob, _| -prob }
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

    # Приводим к RGB и 8-бит, альфа-канал PNG отбрасываем
    cropped = cropped.colourspace(:srgb)
    cropped = cropped.cast(:uchar)
    cropped = cropped.extract_band(0, n: 3) if cropped.bands > 3

    # Нормализация (val / 255 - mean) / std в vips, а не циклом Ruby по 150 тыс. значений
    normalized = cropped.linear(NORM_SCALE, NORM_OFFSET)

    # vips хранит пиксели как HWC (RGBRGB…), модели нужен [1, 3, H, W]: каналы друг за другом
    planes = normalized.bandsplit.map(&:write_to_memory).join
    tensor = OnnxRuntime::OrtValue.from_shape_and_type([ 1, 3, IMAGE_SIZE, IMAGE_SIZE ], :float)
    tensor.data_ptr.put_bytes(0, planes)
    tensor
  end

  def softmax(x)
    exp_x = x.map { |val| Math.exp(val - x.max) }
    sum_exp = exp_x.sum
    exp_x.map { |val| val / sum_exp }
  end
end
