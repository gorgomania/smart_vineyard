# Настоящая картинка 1×1: ActiveStorage анализирует вложение через libvips, и на поддельных байтах
# тот сыплет VIPS-WARNING «Premature end of JPEG file» в вывод тестов
PIXEL_JPEG = Rails.root.join("spec/fixtures/files/pixel.jpg")

FactoryBot.define do
  factory :media_item do
    association :folder

    trait :with_image do
      after(:create) do |item|
        item.media.attach(
          io: File.open(PIXEL_JPEG),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    trait :with_named_image do
      transient { image_filename { "test.jpg" } }

      after(:create) do |item, evaluator|
        item.media.attach(
          io: File.open(PIXEL_JPEG),
          filename: evaluator.image_filename,
          content_type: "image/jpeg"
        )
      end
    end
  end
end
