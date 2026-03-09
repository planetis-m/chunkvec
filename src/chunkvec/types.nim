import openai/core

const
  NoPositionFilter* = -1

type
  ChunkKind* = enum
    none,
    source,
    derived

  ChunkMetadata* = object
    docId*: string
    kind*: ChunkKind
    position*: int
    label*: string

  SearchFilters* = object
    docId*: string
    kind*: ChunkKind
    position*: int = NoPositionFilter
    labelSubstring*: string

  NetworkConfig* = object
    maxInflight*: int
    totalTimeoutMs*: int
    maxRetries*: int

  SqliteConfig* = object
    extensionPath*: string

  RuntimeConfig* = object
    inputPath*: string
    dbPath*: string
    sourcePath*: string
    searchFilters*: SearchFilters
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
    NetworkError,
    Timeout,
    RateLimit,
    HttpError,
    PayloadError,
    DatabaseError

  SearchResult* = object
    id*: int64
    distance*: float
    source*: string
    ordinal*: int
    text*: string
    metadata*: ChunkMetadata

proc parseChunkKind*(text: string): ChunkKind {.inline.} =
  case text
  of "source":
    result = source
  of "derived":
    result = derived
  else:
    result = none

proc hasFilters*(filters: SearchFilters): bool {.inline.} =
  result = filters.docId.len > 0 or filters.kind != none or
    filters.position != NoPositionFilter or filters.labelSubstring.len > 0
