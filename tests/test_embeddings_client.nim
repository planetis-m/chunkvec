import std/[sequtils, strformat, strutils, unittest]
import openai/embeddings
import ../src/chunkvec/[constants, embeddings_client, types]

proc makeBody(vectorLen: int): string =
  let values =
    if vectorLen > 0:
      newSeqWith(vectorLen, "0.5").join(",")
    else:
      ""
  result = fmt"""{{
  "data": [
    {{
      "embedding": [{values}],
      "index": 0
    }}
  ],
  "model": "{Model}",
  "usage": {{
    "prompt_tokens": 1,
    "total_tokens": 1
  }}
}}"""

proc testBuildEmbeddingParams() =
  let params = buildEmbeddingParams(RuntimeConfig(), "hello")
  doAssert params.model == Model
  doAssert params.input == "hello"
  doAssert params.encoding_format == EncodingFormat

proc parseChunkvecEmbedding(body: string): seq[float32] =
  var parsed: EmbeddingCreateResult
  if not embeddingParse(body, parsed):
    raise newException(ValueError, "failed to parse embeddings response")
  if embeddings(parsed) == 0:
    raise newException(ValueError, "embeddings response had no vectors")
  result = embedding(parsed)

proc testChunkvecEmbeddingParseOk() =
  let values = parseChunkvecEmbedding(makeBody(4))
  doAssert values.len == 4
  doAssert values[0] == 0.5'f32

proc testChunkvecEmbeddingParseMalformedJson() =
  expect ValueError:
    discard parseChunkvecEmbedding("{")

proc testChunkvecEmbeddingParseNoVectors() =
  expect ValueError:
    discard parseChunkvecEmbedding("""{
      "data": [],
      "model": "test",
      "usage": {"prompt_tokens": 1, "total_tokens": 1}
    }""")

when isMainModule:
  testBuildEmbeddingParams()
  testChunkvecEmbeddingParseOk()
  testChunkvecEmbeddingParseMalformedJson()
  testChunkvecEmbeddingParseNoVectors()
