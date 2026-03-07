let tests = [
  "deps/openai/tests/test_openai_embeddings.nim",
  "tests/test_chunk_parse.nim",
  "tests/test_request_id_codec.nim",
  "tests/test_vector_blob.nim",
  "tests/test_sqlite_vector_integration.nim"
]

for path in tests:
  exec "nim c -r --hints:off " & path
