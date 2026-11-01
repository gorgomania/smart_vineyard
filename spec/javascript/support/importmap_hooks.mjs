// Модули в app/javascript импортируют друг друга по именам из importmap ("utils/geometry_helpers",
// см. pin_all_from в config/importmap.rb). Браузер разрешает их по importmap, Node — через этот хук
const JAVASCRIPT_ROOT = new URL("../../../app/javascript/", import.meta.url)

export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("utils/")) {
    return { url: new URL(`${specifier}.js`, JAVASCRIPT_ROOT).href, format: "module", shortCircuit: true }
  }
  return nextResolve(specifier, context)
}
