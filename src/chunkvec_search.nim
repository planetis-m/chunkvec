import std/[os, strutils]
import relay
import ./chunkvec/[chunk_store, constants, embeddings_client, logging, runtime_config,
  search_input, types]

proc shutdownRelay(client: Relay; shouldAbort: bool) =
  if shouldAbort:
    client.abort()
  else:
    client.close()

proc renderResult(row: SearchResult; rank: int) =
  let header = $rank & ". distance=" & formatFloat(row.distance, ffDecimal, 6) &
    " source=" & row.source & " ordinal=" & $row.ordinal &
    " page=" & $row.metadata.pageNumber
  if row.metadata.section.len == 0:
    echo header
  else:
    echo header, " section=\"", row.metadata.section, "\""
  echo row.text

proc runSearchApp*(): int =
  var client: Relay = nil
  var shouldAbort = false
  var db: DbConn
  var dbOpened = false

  try:
    let cfg = buildRuntimeConfig(commandLineParams())
    if cfg.openaiConfig.apiKey.len == 0:
      raise newException(ValueError,
        "missing API key; set DEEPINFRA_API_KEY or api_key in config.json")
    if not fileExists(cfg.inputPath):
      raise newException(ValueError, "input file does not exist: " & cfg.inputPath)
    if not fileExists(cfg.dbPath):
      raise newException(ValueError, "database does not exist: " & cfg.dbPath)

    let searchInput = parseSearchInput(cfg.inputPath, readFile(cfg.inputPath))
    if searchInput.queryText.len == 0:
      raise newException(ValueError, "query text must be provided in input file")

    client = newRelay(
      maxInFlight = 1,
      defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
    )

    let queryVector = requestEmbeddingWithRetry(client, cfg, searchInput.queryText)

    db = openDatabase(cfg.dbPath)
    dbOpened = true
    db.loadExtension(cfg.sqliteConfig.extensionPath)
    db.initSchema()
    db.initializeVectorTable()

    let rows = db.searchChunks(queryVector, cfg.topK, searchInput.filters)
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
