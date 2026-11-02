import SparkMD5 from "spark-md5"

// Кусками, как FileChecksum в ActiveStorage: в памяти одновременно не больше одного куска
export const CHUNK_SIZE = 2 * 1024 * 1024

// MD5 файла в base64 — то, что ActiveStorage кладёт в blob.checksum и сверяет при приёме файла.
// Считаем сами, а не внутри DirectUpload: тот не сообщает прогресс, и на больших файлах «Подготовка»
// минутами стоит без движения. onProgress(прочитано байт) — после каждого куска; signal — отмена
// (файл убрали из списка): расчёт прерывается с AbortError
export async function fileChecksum(file, { onProgress = () => {}, signal } = {}) {
  const md5 = new SparkMD5.ArrayBuffer()
  let start = 0
  do {
    signal?.throwIfAborted()
    const end = Math.min(start + CHUNK_SIZE, file.size)
    md5.append(await file.slice(start, end).arrayBuffer())
    start = end
    onProgress(start)
  } while (start < file.size)
  return btoa(md5.end(true))
}
