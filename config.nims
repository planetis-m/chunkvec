when defined(threadSanitizer) or defined(addressSanitizer):
  switch("define", "useMalloc")
elif not defined(useMalloc):
  switch("define", "useMimalloc")
