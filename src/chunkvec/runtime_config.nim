import std/[envvars, files, parseopt, paths]
from std/os import getAppDir
import jsonx
import openai/core
import ./[constants, logging, types]
import ./sqlite_vector_paths

{.define: jsonxLenient.}

type
  JsonRuntimeConfig = object
    api_key: string
    api_url: string
    max_inflight: int
    max_retries: int
    total_timeout_ms: int
    top_k: int

const
  IngestHelpText = """
Usage:
  chunkvec_ingest INPUT.txt DB.sqlite

Options:
  --help, -h       Show this help and exit.
"""

  SearchHelpText = """
Usage:
  chunkvec_search DB.sqlite < QUERY.txt

Options:
  --help, -h       Show this help and exit.
"""

proc cliError(message, helpText: string) =
  quit(message & "\n\n" & helpText, ExitFatalRuntime)

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    api_url: ApiUrl,
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

proc buildRuntimeConfig(): RuntimeConfig =
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedApiUrl = ifNonEmpty(rawConfig.api_url, ApiUrl)

  result = RuntimeConfig(
    breakMarker: BreakMarker,
    openaiConfig: OpenAIConfig(
      url: resolvedApiUrl,
      apiKey: resolvedApiKey
    ),
    networkConfig: NetworkConfig(
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      totalTimeoutMs: ifPositive(rawConfig.total_timeout_ms, TotalTimeoutMs),
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries),
      topK: ifPositive(rawConfig.top_k, TopK)
    ),
    sqliteConfig: SqliteConfig(
      extensionPath: extensionPath()
    )
  )

proc parseIngestCliArgs(cliArgs: seq[string]): tuple[inputPath, dbPath: string] =
  result = (inputPath: "", dbPath: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = parser.key
      elif result.dbPath.len == 0:
        result.dbPath = parser.key
      else:
        cliError("too many positional arguments", IngestHelpText)
    of cmdLongOption:
      if key == "help":
        quit(IngestHelpText, ExitAllOk)
      else:
        cliError("unknown option: --" & key, IngestHelpText)
    of cmdShortOption:
      if key == "h":
        quit(IngestHelpText, ExitAllOk)
      else:
        cliError("unknown option: -" & key, IngestHelpText)
    of cmdEnd:
      discard

  if result.inputPath.len == 0:
    cliError("missing required INPUT.txt argument", IngestHelpText)
  if result.dbPath.len == 0:
    cliError("missing required DB.sqlite argument", IngestHelpText)

proc parseSearchCliArgs(cliArgs: seq[string]): string =
  result = ""
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.len == 0:
        result = parser.key
      else:
        cliError("too many positional arguments", SearchHelpText)
    of cmdLongOption:
      if key == "help":
        quit(SearchHelpText, ExitAllOk)
      else:
        cliError("unknown option: --" & key, SearchHelpText)
    of cmdShortOption:
      if key == "h":
        quit(SearchHelpText, ExitAllOk)
      else:
        cliError("unknown option: -" & key, SearchHelpText)
    of cmdEnd:
      discard

  if result.len == 0:
    cliError("missing required DB.sqlite argument", SearchHelpText)

proc buildIngestRuntimeConfig*(cliArgs: seq[string]): IngestCliConfig =
  let parsed = parseIngestCliArgs(cliArgs)
  result = IngestCliConfig(
    inputPath: parsed.inputPath,
    dbPath: parsed.dbPath,
    runtime: buildRuntimeConfig()
  )

proc buildSearchRuntimeConfig*(cliArgs: seq[string]): SearchCliConfig =
  let parsed = parseSearchCliArgs(cliArgs)
  result = SearchCliConfig(
    dbPath: parsed,
    runtime: buildRuntimeConfig()
  )
