import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { layoutRows, rowBushCount } from "utils/vineyard_rows"
import { parseWKT } from "utils/wkt"
import { GeometryHelpers } from "utils/geometry_helpers"

// Общие эталоны с серверной копией раскладки (VineyardLayout, spec/services/vineyard_layout_spec.rb)
const { cases } = JSON.parse(readFileSync(new URL("../fixtures/files/vineyard_layouts.json", import.meta.url)))

for (const c of cases) {
  test(c.name, () => {
    const rows = layoutRows(parseWKT(c.polygon), c.reference_side_index, c.row_spacing)
    assert.deepEqual(rows.map(r => rowBushCount(r.segments, c.bush_spacing)), c.bushes_per_row)
    assert.equal(GeometryHelpers.calculateArea(parseWKT(c.polygon)), c.area_hectares)
  })
}
