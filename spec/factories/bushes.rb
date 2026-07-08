FactoryBot.define do
  factory :bush do
    association :row
    association :vineyard
    sequence(:bush_number)
  end
end
