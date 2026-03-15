import std/os
import relay
import ./chunkvec/[constants, chunk_store, input_chunks, logging, pipeline, runtime_config, types]

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
    let cfg = buildRuntimeConfig(commandLineParams())
    if cfg.openaiConfig.apiKey.len == 0:
      raise newException(ValueError,
        "missing API key; set DEEPINFRA_API_KEY or api_key in config.json")
    if not fileExists(cfg.inputPath):
      raise newException(ValueError, "input file does not exist: " & cfg.inputPath)
    if cfg.searchFilters.docId.len == 0:
      raise newException(ValueError, "missing required --doc")
    if cfg.searchFilters.kind == none:
      raise newException(ValueError, "missing required --kind")

    let chunks = loadInputChunks(cfg.inputPath)
    if chunks.len == 0:
      raise newException(ValueError, "input did not produce any non-empty chunks")

    let sourceName =
      if cfg.sourcePath.len > 0: cfg.sourcePath
      else: cfg.inputPath

    db = openDatabase(cfg.dbPath)
    dbOpened = true
    db.initSchema()

    var pipelineResult = (allSucceeded: true, wroteRows: false)
    db.beginTransaction()
    transactionOpen = true
    let pending = db.selectMissingChunks(
      cfg.sourcePath,
      cfg.searchFilters.docId,
      cfg.searchFilters.kind,
      chunks
    )
    if pending.skipped > 0:
      logInfo("resume: skipped " & $pending.skipped &
        " already-ingested chunk(s); processing " & $pending.missing.len &
        " missing chunk(s)")

    if pending.missing.len == 0:
      logInfo("all requested chunks are already stored; nothing to do")
      result = ExitAllOk
    else:
      logInfo("starting embedding pipeline for " & $pending.missing.len &
        " missing chunk(s) from " & sourceName & ", please wait...")
      db.loadExtension(cfg.sqliteConfig.extensionPath)
      db.initializeVectorTable(cfg.embeddingDimension)

      var insertStmt = db.prepareInsertStatement()
      try:
        client = newRelay(
          maxInFlight = cfg.networkConfig.maxInflight,
          defaultTimeoutMs = cfg.networkConfig.totalTimeoutMs
        )

        pipelineResult = runPipeline(cfg, pending.missing, client, db, insertStmt)
      finally:
        insertStmt.finalize()

      if pipelineResult.wroteRows:
        db.rebuildQuantization()

      if pipelineResult.allSucceeded:
        result = ExitAllOk
      else:
        logWarn("embedding pipeline completed with partial failures; some chunks were not stored")
        result = ExitPartialFailure

    db.commitTransaction()
    transactionOpen = false
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
