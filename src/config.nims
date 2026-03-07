# config.nims for src/
switch("mm", "atomicArc")

import std/os
import mimalloc/config

switch("define", "jsonxLenient")
switch("passC", "-DCURL_DISABLE_TYPECHECK")
switch("passC", "-I" & thisDir() / "../third_party/sqlite")

when not defined(windows):
  switch("passL", "-lcurl")
  when fileExists("/lib64/libsqlite3.so.0"):
    switch("passL", "/lib64/libsqlite3.so.0")
  elif fileExists("/usr/lib64/libsqlite3.so.0"):
    switch("passL", "/usr/lib64/libsqlite3.so.0")
  else:
    switch("passL", "-lsqlite3")

when defined(macosx):
  switch("passC", "-I" & staticExec("brew --prefix curl") & "/include")
  switch("passL", "-L" & staticExec("brew --prefix curl") & "/lib")
elif defined(windows):
  switch("cc", "vcc")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
  switch("passC", "-I" & vcpkgRoot & "/include")
  switch("passL", vcpkgRoot & "/lib/libcurl.lib")
  switch("passL", vcpkgRoot & "/lib/sqlite3.lib")

when defined(threadSanitizer) or defined(addressSanitizer):
  switch("debugger", "native")
  switch("define", "noSignalHandler")

  when defined(windows):
    when defined(addressSanitizer):
      switch("passC", "/fsanitize=address")
    else:
      {.warning: "Thread Sanitizer is not supported on Windows.".}
  else:
    when defined(threadSanitizer):
      switch("passC", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
      switch("passL", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
    elif defined(addressSanitizer):
      switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
      switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
