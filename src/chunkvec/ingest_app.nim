import std/os
import relay
import ./[constants, chunk_store, input_chunks, logging, pipeline, runtime_config, types]

proc shutdownRelay(client: Relay; shouldAbort: bool) =
  if shouldAbort:
    client.abort()
  else:
    client.close()

proc runIngestApp*(): int =
  var client: Relay = nil
  var shouldAbort = false
  var db: DbConn
  var dbOpened = false
  var transactionOpen = false

  try:
    let cli = buildIngestRuntimeConfig(commandLineParams())
    let cfg = cli.runtime
    if cfg.openaiConfig.apiKey.len == 0:
      raise newException(ValueError,
        "missing API key; set DEEPINFRA_API_KEY or api_key in config.json")
    if not fileExists(cli.inputPath):
      raise newException(ValueError, "input file does not exist: " & cli.inputPath)
    if not fileExists(cfg.sqliteConfig.extensionPath):
      raise newException(ValueError,
        "sqlite-vector extension does not exist: " & cfg.sqliteConfig.extensionPath)

    let chunks = loadInputChunks(cli.inputPath, cfg.breakMarker)
    if chunks.len == 0:
      raise newException(ValueError, "input did not produce any non-empty chunks")

    logInfo("starting embedding pipeline for " & $chunks.len & " chunk(s) from " &
      chunks[0].source & ", please wait...")

    db = openDatabase(cli.dbPath)
    dbOpened = true
    db.loadExtension(cfg.sqliteConfig.extensionPath)
    db.initSchema()
    db.initializeVectorTable()

    var insertStmt = db.prepareInsertStatement()
    var pipelineResult: tuple[allSucceeded, wroteRows: bool]
    try:
      db.beginTransaction()
      transactionOpen = true

      client = newRelay(
        maxInFlight = cfg.networkConfig.maxInflight,
        defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
      )

      pipelineResult = runPipeline(cfg, chunks, client, db, insertStmt)

      db.commitTransaction()
      transactionOpen = false
    finally:
      insertStmt.finalize()

    if pipelineResult.wroteRows:
      db.rebuildQuantization()

    result = if pipelineResult.allSucceeded: ExitAllOk else: ExitPartialFailure
  except CatchableError:
    logError(getCurrentExceptionMsg())
    shouldAbort = true
    if transactionOpen and dbOpened:
      try:
        db.rollbackTransaction()
      except CatchableError:
        discard
    result = ExitFatalRuntime
  finally:
    if not client.isNil:
      shutdownRelay(client, shouldAbort)
    if dbOpened:
      db.close()

when isMainModule:
  quit(runIngestApp())
