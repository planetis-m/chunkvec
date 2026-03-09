import std/[monotimes, os, random, times]
import relay
import openai/[core, embeddings, retry]
import ./[embeddings_client, request_id_codec, retry_and_errors, retry_queue,
  chunk_store, types]

const
  RetryPollSliceMs = 25

type
  PipelineState = object
    inFlightCount: int
    activeCount: int
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    wroteRows: bool
    rng: Rand

proc initPipelineState(total: int): PipelineState =
  PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    allSucceeded: true,
    wroteRows: false,
    rng: initRand(getMonoTime().ticks)
  )

proc insertRecord(db: DbConn; insertStmt: SqlPrepared; record: sink ChunkRecord;
    state: var PipelineState) =
  db.exec(
    insertStmt,
    record.chunk.source,
    record.chunk.ordinal,
    record.chunk.text,
    record.embedding,
    record.chunk.metadata.docId,
    $record.chunk.metadata.kind,
    record.chunk.metadata.position,
    record.chunk.metadata.label
  )
  state.wroteRows = true

proc finalizeChunk(state: var PipelineState; succeeded: bool) =
  if not succeeded:
    state.allSucceeded = false
  dec state.remaining

proc startBatchIfAny(client: Relay; state: var PipelineState) =
  if state.submitBatch.len > 0:
    client.startRequests(state.submitBatch)

proc queueAttempt(cfg: RuntimeConfig; chunks: seq[InputChunk]; seqId, attempt: int;
    state: var PipelineState): bool =
  let requestId = packRequestId(seqId, attempt)

  try:
    embeddingAdd(
      state.submitBatch,
      cfg.openaiConfig,
      params = buildEmbeddingParams(cfg, chunks[seqId].text),
      requestId = requestId,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    )
    inc state.inFlightCount
    result = true
  except CatchableError:
    state.finalizeChunk(succeeded = false)

proc submitDueRetries(cfg: RuntimeConfig; chunks: seq[InputChunk]; maxInFlight: int;
    state: var PipelineState) =
  if state.inFlightCount < maxInFlight:
    let now = getMonoTime()
    var retryItem: RetryItem
    while state.inFlightCount < maxInFlight and
        popDueRetry(state.retryQueue, now, retryItem):
      if not queueAttempt(cfg, chunks, retryItem.seqId, retryItem.attempt, state):
        dec state.activeCount

proc submitFreshAttempts(cfg: RuntimeConfig; chunks: seq[InputChunk]; maxInFlight: int;
    state: var PipelineState) =
  if state.activeCount < maxInFlight and state.nextSubmitSeqId < chunks.len:
    let capacity = maxInFlight - state.activeCount
    var added = 0
    while added < capacity and state.nextSubmitSeqId < chunks.len:
      inc state.activeCount
      if queueAttempt(cfg, chunks, state.nextSubmitSeqId, 1, state):
        inc added
      else:
        dec state.activeCount
      inc state.nextSubmitSeqId

proc processEmbeddingSuccess(cfg: RuntimeConfig; chunks: seq[InputChunk]; seqId: int;
    body: string; db: DbConn; insertStmt: SqlPrepared; state: var PipelineState) =
  var parsed: EmbeddingCreateResult
  if not embeddingParse(body, parsed):
    state.finalizeChunk(succeeded = false)
  elif embeddings(parsed) == 0:
    state.finalizeChunk(succeeded = false)
  else:
    let embeddingLen = embedding(parsed).len
    if embeddingLen != cfg.embeddingDimension:
      state.finalizeChunk(succeeded = false)
    else:
      let record = ChunkRecord(
        chunk: chunks[seqId],
        embedding: move embedding(parsed)
      )
      db.insertRecord(insertStmt, record, state)
      state.finalizeChunk(succeeded = true)

proc processResult(cfg: RuntimeConfig; chunks: seq[InputChunk]; item: RequestResult;
    maxAttempts: int; retryPolicy: RetryPolicy; db: DbConn; insertStmt: SqlPrepared;
    state: var PipelineState) =
  let requestId = item.response.request.requestId
  let meta = unpackRequestId(requestId)
  let seqId = meta.seqId
  let attempt = meta.attempt
  dec state.inFlightCount

  if shouldRetry(item, attempt, maxAttempts):
    let delayMs = retryDelayMs(state.rng, attempt, retryPolicy)
    state.retryQueue.addRetry(RetryItem(
      seqId: seqId,
      attempt: attempt + 1,
      dueAt: getMonoTime() + initDuration(milliseconds = delayMs)
    ))
  else:
    if item.error.kind != teNone or not isHttpSuccess(item.response.code):
      state.finalizeChunk(succeeded = false)
    else:
      processEmbeddingSuccess(cfg, chunks, seqId, item.response.body, db, insertStmt, state)
    dec state.activeCount

proc drainReadyResults(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxAttempts: int; retryPolicy: RetryPolicy; db: DbConn; insertStmt: SqlPrepared;
    state: var PipelineState): bool =
  result = false
  var item: RequestResult
  while client.pollForResult(item):
    processResult(cfg, chunks, item, maxAttempts, retryPolicy, db, insertStmt, state)
    result = true

proc waitForSingleResult(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxAttempts: int; retryPolicy: RetryPolicy; db: DbConn; insertStmt: SqlPrepared;
    state: var PipelineState) =
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(cfg, chunks, item, maxAttempts, retryPolicy, db, insertStmt, state)

proc waitForProgress(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxInFlight, maxAttempts: int; retryPolicy: RetryPolicy; db: DbConn;
    insertStmt: SqlPrepared; state: var PipelineState) =
  if state.inFlightCount == 0:
    let sleepMs = nextRetryDelayMs(state.retryQueue)
    if sleepMs < 0:
      raise newException(ValueError, "pipeline stalled before all results arrived")
    if sleepMs > 0:
      sleep(sleepMs)
  else:
    let nextRetryMs = nextRetryDelayMs(state.retryQueue)
    if nextRetryMs < 0:
      waitForSingleResult(cfg, chunks, client, maxAttempts, retryPolicy, db, insertStmt,
        state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(cfg, chunks, client, maxAttempts, retryPolicy, db, insertStmt,
        state)
    elif nextRetryMs > 0:
      sleep(min(RetryPollSliceMs, nextRetryMs))

proc runPipeline*(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    db: DbConn; insertStmt: SqlPrepared): tuple[
      allSucceeded: bool, wroteRows: bool] =
  let total = chunks.len
  let maxInFlight = max(1, cfg.networkConfig.maxInflight)
  let maxAttempts = max(1, cfg.networkConfig.maxRetries + 1)
  let retryPolicy = defaultRetryPolicy(maxAttempts = maxAttempts)
  ensureRequestIdCapacity(total, maxAttempts)

  var state = initPipelineState(total)

  while state.remaining > 0:
    submitDueRetries(cfg, chunks, maxInFlight, state)
    submitFreshAttempts(cfg, chunks, maxInFlight, state)
    startBatchIfAny(client, state)
    let drained = drainReadyResults(cfg, chunks, client, maxAttempts, retryPolicy, db,
      insertStmt, state)

    if state.remaining > 0 and not drained:
      waitForProgress(cfg, chunks, client, maxInFlight, maxAttempts, retryPolicy, db,
        insertStmt, state)

  result = (allSucceeded: state.allSucceeded, wroteRows: state.wroteRows)
