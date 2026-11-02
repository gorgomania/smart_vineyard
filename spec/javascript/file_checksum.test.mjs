import { test } from "node:test"
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { fileChecksum, CHUNK_SIZE } from "utils/file_checksum"

const reference = (bytes) => createHash("md5").update(bytes).digest("base64")

function randomBytes(size) {
  const bytes = new Uint8Array(size)
  for (let i = 0; i < size; i++) bytes[i] = (i * 31 + (i >> 8)) & 0xff
  return bytes
}

// Сервер сверяет именно этот формат (base64 от MD5): расхождение — «Error storing … Status: 422»
test("matches MD5 base64 for files smaller than, equal to and spanning several chunks", async () => {
  for (const size of [ 1, 1000, CHUNK_SIZE, CHUNK_SIZE + 1, 2 * CHUNK_SIZE + 12345 ]) {
    const bytes = randomBytes(size)
    assert.equal(await fileChecksum(new Blob([ bytes ])), reference(bytes), `size ${size}`)
  }
})

test("handles an empty file", async () => {
  assert.equal(await fileChecksum(new Blob([])), reference(new Uint8Array(0)))
})

test("reports progress after every chunk, ending at the file size", async () => {
  const size = 2 * CHUNK_SIZE + 10
  const progress = []
  await fileChecksum(new Blob([ randomBytes(size) ]), { onProgress: bytes => progress.push(bytes) })
  assert.deepEqual(progress, [ CHUNK_SIZE, 2 * CHUNK_SIZE, size ])
})

test("stops when aborted", async () => {
  const controller = new AbortController()
  const read = fileChecksum(new Blob([ randomBytes(3 * CHUNK_SIZE) ]), {
    signal: controller.signal,
    onProgress: () => controller.abort()
  })
  await assert.rejects(read, { name: "AbortError" })
})
