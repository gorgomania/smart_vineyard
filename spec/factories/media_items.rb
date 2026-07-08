FactoryBot.define do
  factory :media_item do
    association :folder

    trait :with_image do
      after(:create) do |item|
        item.media.attach(
          io: StringIO.new("\xFF\xD8\xFF\xE0fake jpeg content"),
          filename: "test.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    trait :with_named_image do
      transient { image_filename { "test.jpg" } }

      after(:create) do |item, evaluator|
        item.media.attach(
          io: StringIO.new("\xFF\xD8\xFF\xE0fake jpeg content"),
          filename: evaluator.image_filename,
          content_type: "image/jpeg"
        )
      end
    end
  end
end
