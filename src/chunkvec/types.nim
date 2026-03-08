import openai/core

type
  NetworkConfig* = object
    model*: string
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int
    topK*: int

  SqliteConfig* = object
    extensionPath*: string

  RuntimeConfig* = object
    breakMarker*: string
    openaiConfig*: OpenAIConfig
    networkConfig*: NetworkConfig
    sqliteConfig*: SqliteConfig

  IngestCliConfig* = object
    inputPath*: string
    dbPath*: string
    runtime*: RuntimeConfig

  SearchCliConfig* = object
    dbPath*: string
    queryPath*: string
    runtime*: RuntimeConfig

  InputChunk* = object
    source*: string
    ordinal*: int
    text*: string
    hasPage*: bool
    page*: int
    section*: string
    metadataJson*: string

  ChunkRecord* = object
    chunk*: InputChunk
    embedding*: seq[float32]
    dimension*: int

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

  DbMetadata* = object
    initialized*: bool
    model*: string
    dimension*: int
    distance*: string
    qtype*: string

  SearchResult* = object
    id*: int64
    distance*: float
    source*: string
    ordinal*: int
    text*: string
    hasPage*: bool
    page*: int
    section*: string
