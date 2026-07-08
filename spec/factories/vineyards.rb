FactoryBot.define do
  factory :vineyard do
    association :user
    name { Faker::Lorem.unique.word.capitalize }
    polygon { "POLYGON((33.47 44.59, 33.48 44.59, 33.48 44.60, 33.47 44.60, 33.47 44.59))" }
    area_hectares { 1.5 }
    total_rows { 5 }
    total_bushes { 50 }
    row_spacing { 2.5 }
    bush_spacing { 1.5 }
  end
end
