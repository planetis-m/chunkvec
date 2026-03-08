import std/[monotimes, os, random]
import relay
import openai/[core, embeddings, retry]
import ./[constants, retry_and_errors, types]

proc buildEmbeddingParams*(cfg: RuntimeConfig; text: sink string): EmbeddingCreateParams =
  embeddingCreate(
    model = cfg.model,
    input = text,
    encodingFormat = EncodingFormat
  )

proc requestEmbeddingWithRetry*(client: Relay; cfg: RuntimeConfig;
    text: sink string): seq[float32] =
  let maxAttempts = max(1, cfg.networkConfig.maxRetries + 1)
  let retryPolicy = defaultRetryPolicy(maxAttempts = maxAttempts)
  var rng = initRand(getMonoTime().ticks)
  var attempt = 1

  while true:
    let item = client.makeRequest(embeddingRequest(
      cfg.openaiConfig,
      buildEmbeddingParams(cfg, text),
      requestId = attempt,
      timeoutMs = cfg.networkConfig.totalTimeoutMs
    ))

    if shouldRetry(item, attempt, maxAttempts):
      let delayMs = retryDelayMs(rng, attempt, retryPolicy)
      inc attempt
      sleep(delayMs)
    else:
      if item.error.kind != teNone or not isHttpSuccess(item.response.code):
        let finalError = classifyFinalError(item)
        raise newException(IOError, finalError.message)
      var parsed: EmbeddingCreateResult
      if not embeddingParse(item.response.body, parsed):
        raise newException(ValueError, "failed to parse embeddings response")
      let embeddingLen = embedding(parsed).len
      if embeddingLen != cfg.embeddingDimension:
        raise newException(ValueError, "embedding dimension mismatch: expected " &
          $cfg.embeddingDimension &
          ", got " & $embeddingLen)
      result = move embedding(parsed)
      break
