import openai/embeddings
import ./[constants, types]

proc buildEmbeddingParams*(cfg: RuntimeConfig; text: sink string): EmbeddingCreateParams =
  embeddingCreate(
    model = Model,
    input = text,
    encodingFormat = EncodingFormat
  )
