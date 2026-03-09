import openai/embeddings
import ../src/chunkvec/[constants, embeddings_client, types]

proc testBuildEmbeddingParams() =
  let cfg = RuntimeConfig(model: Model)
  let params = buildEmbeddingParams(cfg, "hello")
  doAssert params.model == cfg.model
  doAssert params.input == "hello"
  doAssert params.encoding_format == EncodingFormat

when isMainModule:
  testBuildEmbeddingParams()
