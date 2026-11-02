// Модули в app/javascript импортируют друг друга по именам из importmap ("utils/geometry_helpers",
// см. pin_all_from в config/importmap.rb). Браузер разрешает их по importmap, Node — через этот хук.
// Скачанные пакеты (bin/importmap pin) лежат в vendor/javascript/<имя>.js
const JAVASCRIPT_ROOT = new URL("../../../app/javascript/", import.meta.url)
const VENDOR_ROOT = new URL("../../../vendor/javascript/", import.meta.url)
const VENDOR_PINS = [ "hash-wasm" ]

export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("utils/")) {
    return { url: new URL(`${specifier}.js`, JAVASCRIPT_ROOT).href, format: "module", shortCircuit: true }
  }
  if (VENDOR_PINS.includes(specifier)) {
    return { url: new URL(`${specifier}.js`, VENDOR_ROOT).href, format: "module", shortCircuit: true }
  }
  return nextResolve(specifier, context)
}
