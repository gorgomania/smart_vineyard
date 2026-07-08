FactoryBot.define do
  factory :row do
    association :vineyard
    sequence(:row_number)
  end
end
