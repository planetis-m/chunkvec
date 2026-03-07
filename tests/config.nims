import std/os

when defined(windows):
  switch("cc", "vcc")
  let vcpkgRoot = getEnv("VCPKG_ROOT", "C:/vcpkg/installed/x64-windows-release")
