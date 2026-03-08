import std/[os, strutils, syncio]
import relay
import openai/[core, embeddings]
import ./[chunk_store, constants, embeddings_client, logging, runtime_config, types]

proc shutdownRelay(client: Relay; shouldAbort: bool) =
  if shouldAbort:
    client.abort()
  else:
    client.close()

proc renderResult(row: SearchResult; rank: int) =
  var header = $rank & ". distance=" & formatFloat(row.distance, ffDecimal, 6) &
    " source=" & row.source & " ordinal=" & $row.ordinal
  if row.hasPage:
    header &= " page=" & $row.page
  if row.section.len > 0:
    header &= " section=" & row.section

  stdout.writeLine(header)
  stdout.writeLine(row.text)
  stdout.writeLine("")

proc runSearchApp*(): int =
  var client: Relay = nil
  var shouldAbort = false
  var db: DbConn
  var dbOpened = false

  try:
    let cli = buildSearchRuntimeConfig(commandLineParams())
    let cfg = cli.runtime
    if cfg.openaiConfig.apiKey.len == 0:
      raise newException(ValueError,
        "missing API key; set DEEPINFRA_API_KEY or api_key in config.json")
    if not fileExists(cli.dbPath):
      raise newException(ValueError, "database does not exist: " & cli.dbPath)
    if not fileExists(cfg.sqliteConfig.extensionPath):
      raise newException(ValueError,
        "sqlite-vector extension does not exist: " & cfg.sqliteConfig.extensionPath)

    let queryText = stdin.readAll().strip()
    if queryText.len == 0:
      raise newException(ValueError, "query text must be provided on stdin")

    client = newRelay(
      maxInFlight = 1,
      defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
    )

    let item = client.makeRequest(embeddingRequest(
      cfg.openaiConfig,
      buildEmbeddingParams(cfg, queryText),
      requestId = 1,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    ))

    if item.error.kind != teNone:
      raise newException(IOError, item.error.message)
    if not isHttpSuccess(item.response.code):
      raise newException(IOError, "embedding request failed with http " &
        $item.response.code)

    var parsed: EmbeddingCreateResult
    if not embeddingParse(item.response.body, parsed):
      raise newException(ValueError, "failed to parse embeddings response")
    if embeddings(parsed) == 0 or embedding(parsed).len == 0:
      raise newException(ValueError, "embeddings response had no vectors")

    let queryVector = embedding(parsed)
    if queryVector.len != EmbeddingDimension:
      raise newException(ValueError,
        "embedding dimension mismatch: expected " & $EmbeddingDimension &
        ", got " & $queryVector.len)

    db = openDatabase(cli.dbPath)
    dbOpened = true
    db.loadExtension(cfg.sqliteConfig.extensionPath)
    db.initSchema()
    db.initializeVectorTable()

    let rows = db.searchChunks(queryVector, cfg.networkConfig.topK)
    for i in 0 ..< rows.len:
      renderResult(rows[i], i + 1)

    result = ExitAllOk
  except CatchableError:
    logError(getCurrentExceptionMsg())
    shouldAbort = true
    result = ExitFatalRuntime
  finally:
    if not client.isNil:
      shutdownRelay(client, shouldAbort)
    if dbOpened:
      db.close()

when isMainModule:
  quit(runSearchApp())
