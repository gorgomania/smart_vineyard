require "rails_helper"

RSpec.describe VineyardLayout do
  # Эталоны общие с JS-раскладкой (spec/javascript/vineyard_layouts.test.mjs): сервер и карта считают одинаково
  layouts = JSON.parse(Rails.root.join("spec/fixtures/files/vineyard_layouts.json").read)["cases"]

  def points(wkt)
    RGeo::Geographic.spherical_factory(srid: 4326).parse_wkt(wkt).exterior_ring.points.map { |p| [ p.y, p.x ] }
  end

  layouts.each do |c|
    it "совпадает с JS: #{c['name']}" do
      layout = described_class.new(points(c["polygon"]), side_index: c["reference_side_index"],
                                   row_spacing: c["row_spacing"], bush_spacing: c["bush_spacing"])
      expect(layout.bushes_per_row).to eq(c["bushes_per_row"])
      # Площадь — разность почти равных слагаемых: последний бит sin у V8 и libm проступает в 11-м знаке.
      # Хранится она до сотых гектара, так что допуск с запасом; кусты же совпадают точно
      expect(layout.area_hectares).to be_within(1e-8).of(c["area_hectares"])
    end
  end

  it "берёт полигон, опорную сторону и шаги из виноградника" do
    c = layouts.first
    vineyard = build(:vineyard, polygon: c["polygon"], reference_side_index: c["reference_side_index"],
                                row_spacing: c["row_spacing"], bush_spacing: c["bush_spacing"])
    expect(described_class.for(vineyard).bushes_per_row).to eq(c["bushes_per_row"])
  end

  # Шаг в базе может быть NULL (CHECK его пропускает): for даёт 0.0, и без проверки цикл рядов бесконечен —
  # миграция пересчёта повисла бы на деплое
  it "пустая раскладка, а не бесконечный цикл, при шаге не больше нуля" do
    points = points(layouts.first["polygon"])
    expect(described_class.new(points, side_index: 0, row_spacing: 0.0, bush_spacing: 1.5).bushes_per_row).to eq([])
    expect(described_class.new(points, side_index: 0, row_spacing: 3.0, bush_spacing: 0.0).bushes_per_row).to eq([])
    vineyard = build(:vineyard, polygon: layouts.first["polygon"], row_spacing: nil, bush_spacing: nil)
    expect(described_class.for(vineyard).bushes_per_row).to eq([])
  end

  it "нет опорной стороны — нет рядов" do
    expect(described_class.new(points(layouts.first["polygon"]), side_index: 9, row_spacing: 3, bush_spacing: 1.5).rows).to eq([])
  end
end
