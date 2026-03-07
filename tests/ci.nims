proc runTest(cmd: string) =
  echo "Running: " & cmd
  exec cmd

task test, "Run CI tests":
  runTest "nim c -r deps/openai/tests/test_openai_embeddings.nim"
  runTest "nim c -r tests/test_chunk_parse.nim"
  runTest "nim c -r tests/test_request_id_codec.nim"
  runTest "nim c -r tests/test_sqlite_vector_integration.nim"
