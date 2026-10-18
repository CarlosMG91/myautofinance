#include <windows.h>
#include <iostream>

// Load only the freshly built private DLL; do not initialize an operation or
// access a real profile. Checks the actual undecorated stdcall Inno ABI.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 1;
  HMODULE module = LoadLibraryExW(argv[1], nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!module) return 2;
  for (const auto* name : {"AfInitialize", "AfInfo", "AfSource", "AfBegin", "AfStage", "AfCommit", "AfAbort", "AfUninstallBegin", "AfUninstallClean", "AfUninstallFinish"})
    if (!GetProcAddress(module, name)) { FreeLibrary(module); return 3; }
  using Info = int (__stdcall*)(unsigned, wchar_t*, unsigned);
  using Abort = int (__stdcall*)();
  using Initialize = int (__stdcall*)(const wchar_t*, const wchar_t*);
  using Begin = int (__stdcall*)(const wchar_t*);
  const auto info = reinterpret_cast<Info>(GetProcAddress(module, "AfInfo"));
  const auto abort = reinterpret_cast<Abort>(GetProcAddress(module, "AfAbort"));
  wchar_t buffer[16]{};
  bool ok = info(0, buffer, 16) == 5 && buffer[0] == L'\0' && abort() == 8;
  const auto initialize = reinterpret_cast<Initialize>(GetProcAddress(module, "AfInitialize"));
  ok = ok && initialize(nullptr, nullptr) == 5;
  for (const auto* name : {"AfStage", "AfCommit", "AfUninstallClean", "AfUninstallFinish"})
    ok = ok && reinterpret_cast<Abort>(GetProcAddress(module, name))() == 5;
  for (const auto* name : {"AfBegin", "AfUninstallBegin"})
    ok = ok && reinterpret_cast<Begin>(GetProcAddress(module, name))(nullptr) == 5;
  FreeLibrary(module);
  std::cout << "Inno stdcall ABI and fail-closed uninitialized state checked; no profile access\n";
  return ok ? 0 : 4;
}
