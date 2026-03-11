import openai/embeddings

const
  DefaultConfigPath* = "config.json"
  AppDataDirName* = "chunkvec"
  DatabaseFilename* = "db.sqlite"

  ApiUrl* = "https://api.deepinfra.com/v1/openai/embeddings"
  Model* = "Qwen/Qwen3-Embedding-0.6B"
  EmbeddingDimension* = 1024
  MaxInflight* = 32
  TotalTimeoutMs* = 120_000
  MaxRetries* = 5
  TopK* = 8
  EncodingFormat* = EmbeddingEncodingFormat.`float`
  VectorType* = "FLOAT32"
  DistanceMetric* = "COSINE"
  QuantizationType* = "UINT8"

  TableName* = "chunks"
  EmbeddingColumn* = "embedding"

  ExitAllOk* = 0
  ExitPartialFailure* = 2
  ExitFatalRuntime* = 3
