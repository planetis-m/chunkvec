import std/[monotimes, os, random, times]
import relay
import openai, openai_embeddings, openai_retry
import ./[embeddings_client, request_id_codec, retry_and_errors, retry_queue,
  sqlite_wrap, types, vector_blob]

const
  RetryPollSliceMs = 25

type
  PipelineState = object
    inFlightCount: int
    activeCount: int
    staged: seq[ChunkResult]
    records: seq[ChunkRecord]
    retryQueue: RetryQueue
    nextSubmitSeqId: int
    nextFinalizeSeqId: int
    remaining: int
    submitBatch: RequestBatch
    allSucceeded: bool
    insertedCount: int
    rng: Rand

proc okChunkResult(attempts: int): ChunkResult {.inline.} =
  ChunkResult(
    attempts: attempts,
    status: ChunkOk,
    errorKind: NoError,
    errorMessage: "",
    httpStatus: 0
  )

proc errorChunkResult(attempts: int; kind: ChunkErrorKind;
    message: sink string; httpStatus = 0): ChunkResult {.inline.} =
  ChunkResult(
    attempts: attempts,
    status: ChunkError,
    errorKind: kind,
    errorMessage: message,
    httpStatus: httpStatus
  )

proc initPipelineState(total: int): PipelineState =
  PipelineState(
    inFlightCount: 0,
    activeCount: 0,
    staged: newSeq[ChunkResult](total),
    records: newSeq[ChunkRecord](total),
    retryQueue: initRetryQueue(),
    nextSubmitSeqId: 0,
    nextFinalizeSeqId: 0,
    remaining: total,
    submitBatch: RequestBatch(),
    allSucceeded: true,
    insertedCount: 0,
    rng: initRand(getMonoTime().ticks)
  )

proc flushOrderedResults(db: Database; insertStmt: Statement; cfg: RuntimeConfig;
    state: var PipelineState; dbMeta: var DbMetadata) =
  while state.nextFinalizeSeqId < state.staged.len and
      state.staged[state.nextFinalizeSeqId].status != ChunkPending:
    if state.staged[state.nextFinalizeSeqId].status != ChunkOk:
      state.allSucceeded = false
    else:
      let record = state.records[state.nextFinalizeSeqId]
      if not dbMeta.initialized:
        dbMeta = configuredMetadata(cfg.networkConfig.model, record.dimension)
        db.writeMetadata(dbMeta)
        db.initializeVectorTable(dbMeta)
      else:
        dbMeta.ensureMetadataCompatible(cfg.networkConfig.model, record.dimension)
      db.insertChunk(insertStmt, record)
      inc state.insertedCount

    state.staged[state.nextFinalizeSeqId] = default(ChunkResult)
    state.records[state.nextFinalizeSeqId] = default(ChunkRecord)
    inc state.nextFinalizeSeqId
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
    state.staged[seqId] = errorChunkResult(
      attempts = attempt,
      kind = NetworkError,
      message = getCurrentExceptionMsg()
    )

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

proc processEmbeddingSuccess(chunks: seq[InputChunk]; seqId, attempt: int; body: string;
    state: var PipelineState) =
  var parsed: EmbeddingCreateResult
  if not embeddingParse(body, parsed):
    state.staged[seqId] = errorChunkResult(
      attempts = attempt,
      kind = PayloadError,
      message = "failed to parse embeddings response"
    )
  elif embeddings(parsed) == 0:
    state.staged[seqId] = errorChunkResult(
      attempts = attempt,
      kind = PayloadError,
      message = "embeddings response had no vectors"
    )
  else:
    let values = embedding(parsed)
    if values.len == 0:
      state.staged[seqId] = errorChunkResult(
        attempts = attempt,
        kind = PayloadError,
        message = "embedding vector was empty"
      )
    else:
      state.records[seqId] = ChunkRecord(
        chunk: chunks[seqId],
        embeddingBlob: floatsToBlob(values),
        dimension: values.len
      )
      state.staged[seqId] = okChunkResult(attempt)

proc processResult(cfg: RuntimeConfig; chunks: seq[InputChunk]; item: RequestResult;
    maxAttempts: int; retryPolicy: RetryPolicy; state: var PipelineState) =
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
      let finalError = classifyFinalError(item)
      state.staged[seqId] = errorChunkResult(
        attempts = attempt,
        kind = finalError.kind,
        message = finalError.message,
        httpStatus = finalError.httpStatus
      )
    else:
      processEmbeddingSuccess(chunks, seqId, attempt, item.response.body, state)
    dec state.activeCount

proc drainReadyResults(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxAttempts: int; retryPolicy: RetryPolicy; state: var PipelineState): bool =
  result = false
  var item: RequestResult
  while client.pollForResult(item):
    processResult(cfg, chunks, item, maxAttempts, retryPolicy, state)
    result = true

proc waitForSingleResult(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxAttempts: int; retryPolicy: RetryPolicy; state: var PipelineState) =
  var item: RequestResult
  if not client.waitForResult(item):
    raise newException(IOError, "relay worker stopped before all results arrived")
  processResult(cfg, chunks, item, maxAttempts, retryPolicy, state)

proc waitForProgress(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    maxInFlight, maxAttempts: int; retryPolicy: RetryPolicy; state: var PipelineState) =
  if state.inFlightCount == 0:
    let sleepMs = nextRetryDelayMs(state.retryQueue)
    if sleepMs < 0:
      raise newException(ValueError, "pipeline stalled before all results arrived")
    if sleepMs > 0:
      sleep(sleepMs)
  else:
    let nextRetryMs = nextRetryDelayMs(state.retryQueue)
    if nextRetryMs < 0:
      waitForSingleResult(cfg, chunks, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs == 0 and state.inFlightCount == maxInFlight:
      waitForSingleResult(cfg, chunks, client, maxAttempts, retryPolicy, state)
    elif nextRetryMs > 0:
      sleep(min(RetryPollSliceMs, nextRetryMs))

proc runPipeline*(cfg: RuntimeConfig; chunks: seq[InputChunk]; client: Relay;
    db: Database; insertStmt: Statement; dbMeta: var DbMetadata): tuple[
      allSucceeded: bool,
      insertedCount: int
    ] =
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
    flushOrderedResults(db, insertStmt, cfg, state, dbMeta)

    let drained = drainReadyResults(cfg, chunks, client, maxAttempts, retryPolicy, state)
    flushOrderedResults(db, insertStmt, cfg, state, dbMeta)

    if state.remaining > 0 and not drained:
      waitForProgress(cfg, chunks, client, maxInFlight, maxAttempts, retryPolicy, state)
      flushOrderedResults(db, insertStmt, cfg, state, dbMeta)

  result = (allSucceeded: state.allSucceeded, insertedCount: state.insertedCount)
