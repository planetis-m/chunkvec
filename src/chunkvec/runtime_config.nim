import std/[appdirs, envvars, files, parseopt, paths, strutils]
from std/dirs import createDir
from std/os import getAppDir
import jsonx
import openai/core
import ./[constants, logging, types]
import ./sqlite_vector_paths

{.define: jsonxLenient.}

type
  CliArgs = object
    inputPath: string
    sourcePath: string
    searchFilters: SearchFilters

  JsonRuntimeConfig = object
    api_key: string
    api_url: string
    model: string
    embedding_dimension: int
    max_inflight: int
    max_retries: int
    total_timeout_ms: int
    top_k: int

const HelpText = """
Usage:
  cvstore --doc=DOC --kind=source|derived [--source=RELATIVEPATH] INPUT.txt
  cvquery [--doc=DOC] [--kind=source|derived] [--page=N] [--label=TEXT] QUERY

Options:
  --doc=DOC        Ingest doc id for cvstore; exact-match doc filter for cvquery.
  --kind=KIND      Ingest kind for cvstore; exact-match kind filter for cvquery.
  --source=PATH    Optional stored chunk source for cvstore.
  --page=N         Exact-match query filter for integer page; requires --doc.
  --label=TEXT     Substring query filter for chunk label.
  --help, -h       Show this help and exit.
"""

proc cliError(message: string) =
  quit(message & "\n\n" & HelpText, ExitFatalRuntime)

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    api_url: ApiUrl,
    model: Model,
    embedding_dimension: EmbeddingDimension,
    max_inflight: MaxInflight,
    max_retries: MaxRetries,
    total_timeout_ms: TotalTimeoutMs,
    top_k: TopK
  )

proc loadOptionalJsonRuntimeConfig(path: Path): JsonRuntimeConfig =
  result = defaultJsonRuntimeConfig()
  if fileExists(path):
    try:
      jsonx.fromFile(path, result)
      logInfo("loaded config from " & $path)
    except CatchableError:
      logWarn("failed to parse config file at " & $path &
        "; using built-in defaults")
  else:
    logInfo("config file not found at " & $path & "; using built-in defaults")

proc resolveApiKey(configApiKey: string): string =
  let envApiKey = getEnv("DEEPINFRA_API_KEY")
  if envApiKey.len > 0:
    result = envApiKey
  else:
    result = configApiKey

template ifNonEmpty(value, fallback: untyped): untyped =
  if value.len > 0: value
  else: fallback

template ifPositive(value, fallback: untyped): untyped =
  if value > 0: value
  else: fallback

template ifNonNegative(value, fallback: untyped): untyped =
  if value >= 0: value
  else: fallback

proc parseSearchFilterPage(val: string): int =
  try:
    result = parseInt(val)
  except ValueError:
    cliError("invalid value for --page: " & val)

proc resolveDbPath(): Path =
  let dbDir = getDataDir() / Path(AppDataDirName) / lastPathPart(getCurrentDir())
  createDir(dbDir)
  result = dbDir / Path(DatabaseFilename)

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(
    inputPath: "",
    sourcePath: "",
    searchFilters: SearchFilters()
  )
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = parser.key
      else:
        cliError("too many positional arguments")
    of cmdLongOption:
      if key == "help":
        quit(HelpText, ExitAllOk)
      elif key == "source":
        if val.len == 0:
          cliError("missing value for --source")
        result.sourcePath = val
      elif key == "doc":
        if val.len == 0:
          cliError("missing value for --doc")
        result.searchFilters.docId = val
      elif key == "kind":
        if val.len == 0:
          cliError("missing value for --kind")
        let parsedKind = parseChunkKind(val)
        if parsedKind == none:
          cliError("invalid value for --kind: " & val)
        result.searchFilters.kind = parsedKind
      elif key == "page":
        if val.len == 0:
          cliError("missing value for --page")
        result.searchFilters.page = parseSearchFilterPage(val)
      elif key == "label":
        if val.len == 0:
          cliError("missing value for --label")
        result.searchFilters.labelSubstring = val
      else:
        cliError("unknown option: --" & key)
    of cmdShortOption:
      if key == "h":
        quit(HelpText, ExitAllOk)
      else:
        cliError("unknown option: -" & key)
    of cmdEnd:
      discard

  if result.inputPath.len == 0:
    cliError("missing required INPUT.txt/QUERY argument")
  if result.searchFilters.page != NoPageFilter and
      result.searchFilters.docId.len == 0:
    cliError("--page requires --doc")

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedApiUrl = ifNonEmpty(rawConfig.api_url, ApiUrl)

  result = RuntimeConfig(
    inputPath: parsed.inputPath,
    dbPath: $resolveDbPath(),
    sourcePath: parsed.sourcePath,
    searchFilters: parsed.searchFilters,
    model: ifNonEmpty(rawConfig.model, Model),
    embeddingDimension: ifPositive(rawConfig.embedding_dimension, EmbeddingDimension),
    topK: ifPositive(rawConfig.top_k, TopK),
    openaiConfig: OpenAIConfig(
      url: resolvedApiUrl,
      apiKey: resolvedApiKey
    ),
    networkConfig: NetworkConfig(
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      totalTimeoutMs: ifPositive(rawConfig.total_timeout_ms, TotalTimeoutMs),
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries)
    ),
    sqliteConfig: SqliteConfig(
      extensionPath: extensionPath()
    )
  )
