import std/[envvars, files, os, parseopt, paths, strutils]
from std/os import getAppDir
import jsonx
import openai
import ./[constants, logging, types]

{.define: jsonxLenient.}

type
  JsonRuntimeConfig = object
    api_key: string
    api_url: string
    model: string
    break_marker: string
    max_inflight: int
    max_retries: int
    total_timeout_ms: int
    vector_extension_path: string
    top_k: int

const
  IngestHelpText = """
Usage:
  chunkvec_ingest INPUT.txt| - DB.sqlite

Options:
  --help, -h       Show this help and exit.
"""

  SearchHelpText = """
Usage:
  chunkvec_search DB.sqlite QUERY|-

Options:
  --help, -h       Show this help and exit.
"""

proc cliError(message, helpText: string) =
  quit(message & "\n\n" & helpText, ExitFatalRuntime)

proc defaultJsonRuntimeConfig(): JsonRuntimeConfig =
  JsonRuntimeConfig(
    api_key: "",
    api_url: ApiUrl,
    model: Model,
    break_marker: BreakMarker,
    max_inflight: MaxInflight,
    max_retries: MaxRetries,
    total_timeout_ms: TotalTimeoutMs,
    vector_extension_path: "third_party/sqlite/vector.so",
    top_k: TopK
  )

proc resolveAppBaseDir(): string =
  let appDir = getAppDir()
  let repoConfigPath = appDir.parentDir / DefaultConfigPath
  if fileExists(appDir / DefaultConfigPath):
    result = appDir
  elif fileExists(repoConfigPath):
    result = appDir.parentDir
  else:
    result = appDir

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

proc resolveExtensionPath(baseDir, rawPath: string): string =
  if rawPath.len == 0:
    result = baseDir / "third_party/sqlite/vector.so"
  elif rawPath.isAbsolute:
    result = rawPath
  else:
    result = baseDir / rawPath

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
  let baseDir = resolveAppBaseDir()
  let configPath = Path(baseDir) / Path(DefaultConfigPath)
  let rawConfig = loadOptionalJsonRuntimeConfig(configPath)
  let resolvedApiKey = resolveApiKey(rawConfig.api_key)
  let resolvedApiUrl = ifNonEmpty(rawConfig.api_url, ApiUrl)
  let resolvedExtensionPath = resolveExtensionPath(baseDir, rawConfig.vector_extension_path)

  result = RuntimeConfig(
    breakMarker: ifNonEmpty(rawConfig.break_marker, BreakMarker),
    openaiConfig: OpenAIConfig(
      url: resolvedApiUrl,
      apiKey: resolvedApiKey
    ),
    networkConfig: NetworkConfig(
      model: ifNonEmpty(rawConfig.model, Model),
      maxInflight: ifPositive(rawConfig.max_inflight, MaxInflight),
      totalTimeoutMs: ifPositive(rawConfig.total_timeout_ms, TotalTimeoutMs),
      maxRetries: ifNonNegative(rawConfig.max_retries, MaxRetries),
      topK: ifPositive(rawConfig.top_k, TopK)
    ),
    sqliteConfig: SqliteConfig(
      extensionPath: resolvedExtensionPath
    )
  )

proc parseIngestCliArgs(cliArgs: seq[string]): tuple[inputPath, dbPath: string] =
  var parser = initOptParser(cliArgs)
  var positional: seq[string]

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      positional.add(parser.key)
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

  if positional.len < 2:
    cliError("missing required INPUT and DB arguments", IngestHelpText)
  if positional.len > 2:
    cliError("too many positional arguments", IngestHelpText)

  result = (inputPath: positional[0], dbPath: positional[1])

proc parseSearchCliArgs(cliArgs: seq[string]): tuple[dbPath, queryText: string] =
  var parser = initOptParser(cliArgs)
  var positional: seq[string]

  for kind, key, val in parser.getopt():
    case kind
    of cmdArgument:
      positional.add(parser.key)
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

  if positional.len < 2:
    cliError("missing required DB and QUERY arguments", SearchHelpText)

  result.dbPath = positional[0]
  result.queryText = positional[1 .. ^1].join(" ")

proc buildIngestRuntimeConfig*(cliArgs: seq[string]): IngestCliConfig =
  let parsed = parseIngestCliArgs(cliArgs)
  result = IngestCliConfig(
    inputPath: parsed.inputPath,
    dbPath: parsed.dbPath,
    runtime: buildRuntimeConfig()
  )

proc buildSearchRuntimeConfig*(cliArgs: seq[string]): SearchCliConfig =
  let parsed = parseSearchCliArgs(cliArgs)
  let queryText =
    if parsed.queryText == "-":
      stdin.readAll().strip()
    else:
      parsed.queryText.strip()

  result = SearchCliConfig(
    dbPath: parsed.dbPath,
    queryText: queryText,
    runtime: buildRuntimeConfig()
  )
