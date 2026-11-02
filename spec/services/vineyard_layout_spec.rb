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

  it "нет опорной стороны — нет рядов" do
    expect(described_class.new(points(layouts.first["polygon"]), side_index: 9, row_spacing: 3, bush_spacing: 1.5).rows).to eq([])
  end
end
