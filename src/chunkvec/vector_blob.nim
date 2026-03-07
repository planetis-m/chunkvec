proc floatsToBlob*(values: openArray[float]): seq[byte] =
  var packed = newSeq[float32](values.len)
  for i in 0 ..< values.len:
    packed[i] = float32(values[i])

  result = newSeq[byte](values.len * sizeof(float32))
  if result.len > 0:
    copyMem(addr result[0], unsafeAddr packed[0], result.len)

proc float32Bytes*(dimensions: int): int {.inline.} =
  result = dimensions * sizeof(float32)
