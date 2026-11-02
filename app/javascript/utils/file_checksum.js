// Крупные куски: в браузере дорого именно чтение файла (каждый кусок идёт из процесса браузера в страницу),
// и 32 МБ читаются в 1,7 раза быстрее, чем 2 МБ, как у DirectUpload (замер в Chrome 02.11).
// В памяти одновременно два куска: считаемый и следующий
export const CHUNK_SIZE = 32 * 1024 * 1024

// MD5 файла в base64 — то, что ActiveStorage кладёт в blob.checksum и сверяет при приёме файла.
// Считаем сами, а не внутри DirectUpload: тот не сообщает прогресс, и на больших файлах «Подготовка»
// минутами стоит без движения. onProgress(прочитано байт) — после каждого куска; signal — отмена
// (файл убрали из списка): расчёт прерывается с AbortError.
// Скорость в Chrome (замер 02.11): MD5 на WebAssembly (hash-wasm) — 365 МБ/с, на чистом JS (SparkMD5, как
// в DirectUpload) — 57; со чтением файла ~115 МБ/с против ~45. Следующий кусок читается, пока считается
// текущий: чтение идёт в процессе браузера и не ждёт расчёта
export async function fileChecksum(file, { onProgress = () => {}, signal } = {}) {
  const { createMD5 } = await import("hash-wasm") // 230 КБ — только когда понадобится
  const md5 = await createMD5()
  md5.init()

  const read = (start) => {
    const chunk = file.slice(start, start + CHUNK_SIZE).arrayBuffer()
    chunk.catch(() => {}) // брошенное при отмене чтение не должно давать «unhandled rejection»
    return chunk
  }

  let start = 0
  let next = read(0)
  do {
    signal?.throwIfAborted()
    const chunk = await next
    const end = Math.min(start + CHUNK_SIZE, file.size)
    if (end < file.size) next = read(end)
    md5.update(new Uint8Array(chunk))
    start = end
    onProgress(start)
  } while (start < file.size)
  return btoa(String.fromCharCode(...md5.digest("binary")))
}
