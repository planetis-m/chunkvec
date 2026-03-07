import ../src/chunkvec/request_id_codec

proc testRoundTrip() =
  let packed = packRequestId(17, 3)
  let unpacked = unpackRequestId(packed)
  doAssert unpacked.seqId == 17
  doAssert unpacked.attempt == 3

proc testCapacityCheck() =
  ensureRequestIdCapacity(128, 8)

when isMainModule:
  testRoundTrip()
  testCapacityCheck()
