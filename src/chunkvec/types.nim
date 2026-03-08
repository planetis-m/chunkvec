import openai/core

type
  NetworkConfig* = object
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int

  SqliteConfig* = object
    extensionPath*: string

  RuntimeConfig* = object
    inputPath*: string
    dbPath*: string
    topK*: int
    openaiConfig*: OpenAIConfig
    networkConfig*: NetworkConfig
    sqliteConfig*: SqliteConfig

  InputChunk* = object
    source*: string
    ordinal*: int
    text*: string
    metadataJson*: string

  ChunkRecord* = object
    chunk*: InputChunk
    embedding*: seq[float32]

  ChunkErrorKind* = enum
    NoError,
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    PayloadError,
    DatabaseError

  ChunkResultStatus* = enum
    ChunkPending = "pending",
    ChunkOk = "ok",
    ChunkError = "error"

  ChunkResult* = object
    attempts*: int
    status*: ChunkResultStatus
    errorKind*: ChunkErrorKind
    errorMessage*: string
    httpStatus*: int

  SearchResult* = object
    id*: int64
    distance*: float
    source*: string
    ordinal*: int
    text*: string
    metadataJson*: string
