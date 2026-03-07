import openai_embeddings
import ./[constants, types]

proc buildEmbeddingParams*(cfg: RuntimeConfig; text: sink string): EmbeddingCreateParams =
  embeddingCreate(
    model = cfg.networkConfig.model,
    input = text,
    encodingFormat = EncodingFormat
  )
