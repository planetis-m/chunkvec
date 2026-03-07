import ../src/chunkvec/vector_blob

proc testFloatBlobPacking() =
  let blob = floatsToBlob([0.5, -1.25, 3.0])
  doAssert blob.len == 3 * sizeof(float32)
  doAssert float32Bytes(3) == blob.len

when isMainModule:
  testFloatBlobPacking()
