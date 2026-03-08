import std/[os, strutils, syncio]
import relay
import ./[chunk_store, constants, embeddings_client, logging, runtime_config, types]

proc shutdownRelay(client: Relay; shouldAbort: bool) =
  if shouldAbort:
    client.abort()
  else:
    client.close()

proc renderResult(row: SearchResult; rank: int) =
  var header = $rank & ". distance=" & formatFloat(row.distance, ffDecimal, 6) &
    " source=" & row.source & " ordinal=" & $row.ordinal
  if row.metadataJson.len > 0:
    header &= " metadata=" & row.metadataJson

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

    let queryVector = requestEmbeddingWithRetry(client, cfg, queryText)

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
