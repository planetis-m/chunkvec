import openai/embeddings

const
  DefaultConfigPath* = "config.json"

  ApiUrl* = "https://api.deepinfra.com/v1/openai/embeddings"
  Model* = "Qwen/Qwen3-Embedding-0.6B"
  BreakMarker* = "<bk>"
  MaxInflight* = 32
  TotalTimeoutMs* = 120_000
  MaxRetries* = 5
  TopK* = 8
  EncodingFormat* = EmbeddingEncodingFormat.`float`
  DistanceMetric* = "COSINE"
  QuantizationType* = "UINT8"

  TableName* = "chunks"
  EmbeddingColumn* = "embedding"
  MetaTableName* = "chunkvec_meta"

  ExitAllOk* = 0
  ExitPartialFailure* = 2
  ExitFatalRuntime* = 3
