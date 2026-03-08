import std/[envvars, files, parseopt, paths]
from std/os import getAppDir
import jsonx
import openai/core
import ./[constants, logging, types]
import ./sqlite_vector_paths

{.define: jsonxLenient.}

type
  CliArgs = object
    inputPath: string
    dbPath: string

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
  cvstore INPUT.txt DB.sqlite
  cvquery QUERY.txt DB.sqlite

Options:
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

proc parseCliArgs(cliArgs: seq[string]): CliArgs =
  result = CliArgs(inputPath: "", dbPath: "")
  var parser = initOptParser(cliArgs)

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      if result.inputPath.len == 0:
        result.inputPath = parser.key
      elif result.dbPath.len == 0:
        result.dbPath = parser.key
      else:
        cliError("too many positional arguments")
    of cmdLongOption:
      if key == "help":
        quit(HelpText, ExitAllOk)
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
    cliError("missing required INPUT.txt argument")
  if result.dbPath.len == 0:
    cliError("missing required DB.sqlite argument")

proc buildRuntimeConfig*(cliArgs: seq[string]): RuntimeConfig =
  let parsed = parseCliArgs(cliArgs)
  let configPath = Path(getAppDir()) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedApiUrl = ifNonEmpty(rawConfig.api_url, ApiUrl)

  result = RuntimeConfig(
    inputPath: parsed.inputPath,
    dbPath: parsed.dbPath,
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
