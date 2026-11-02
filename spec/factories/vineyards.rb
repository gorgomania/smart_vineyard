FactoryBot.define do
  factory :vineyard do
    association :user
    name { Faker::Lorem.unique.word.capitalize }
    # Прямоугольник ~79 × 56 м (0.44 га): сервер сам считает площадь, а она в пределах Vineyard::MAX_AREA_HECTARES
    polygon { "POLYGON((33.56 44.744, 33.561 44.744, 33.561 44.7445, 33.56 44.7445, 33.56 44.744))" }
    area_hectares { 1.5 }
    total_rows { 5 }
    total_bushes { 50 }
    row_spacing { 2.5 }
    bush_spacing { 1.5 }
  end
end
