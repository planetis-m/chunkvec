import openai/core

const
  NoPageFilter* = -1

type
  ChunkMetadata* = object
    pageNumber*: int
    section*: string

  SearchFilters* = object
    pageNumber*: int = NoPageFilter
    sectionSubstring*: string

  SearchInput* = object
    queryText*: string
    filters*: SearchFilters

  NetworkConfig* = object
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int

  SqliteConfig* = object
    extensionPath*: string

  RuntimeConfig* = object
    inputPath*: string
    dbPath*: string
    model*: string
    embeddingDimension*: int
    topK*: int
    openaiConfig*: OpenAIConfig
    networkConfig*: NetworkConfig
    sqliteConfig*: SqliteConfig

  InputChunk* = object
    source*: string
    ordinal*: int
    text*: string
    metadata*: ChunkMetadata

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
    metadata*: ChunkMetadata

proc initSearchFilters*(): SearchFilters {.inline.} =
  result = SearchFilters(pageNumber: NoPageFilter, sectionSubstring: "")

proc hasFilters*(filters: SearchFilters): bool {.inline.} =
  result = filters.pageNumber != NoPageFilter or filters.sectionSubstring.len > 0
