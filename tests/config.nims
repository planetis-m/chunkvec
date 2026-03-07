import std/os

switch("passC", "-I" & thisDir() / "../third_party/sqlite")

when defined(windows):
  switch("cc", "vcc")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
  switch("passL", vcpkgRoot & "/lib/sqlite3.lib")
elif defined(macosx):
  switch("passL", "-lsqlite3")
else:
  when fileExists("/lib64/libsqlite3.so.0"):
    switch("passL", "/lib64/libsqlite3.so.0")
  elif fileExists("/usr/lib64/libsqlite3.so.0"):
    switch("passL", "/usr/lib64/libsqlite3.so.0")
  else:
    switch("passL", "-lsqlite3")
