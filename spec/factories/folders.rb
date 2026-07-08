FactoryBot.define do
  factory :folder do
    association :user
    sequence(:title) { |n| "Folder #{n}" }
  end
end
