#include "windows_session_store.h"

#include <windows.h>
#include <shlobj.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

using namespace autofinance::maintenance;
#define CHECK(x) do { if (!(x)) throw std::runtime_error(#x); } while (false)
namespace {
std::wstring TestRoot() {
  PWSTR path = nullptr;
  CHECK(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path) == S_OK);
  const std::wstring root = std::wstring(path) + L"\\AutofinanceMaintenanceTest\\";
  CoTaskMemFree(path);
  return root;
}
std::wstring Lower(std::wstring s) { CharLowerBuffW(s.data(), static_cast<DWORD>(s.size())); return s; }
}  // namespace
int wmain(int argc, wchar_t** argv) {
  // No registry/credential access until ALL explicit isolation guards pass.
  wchar_t user[256]{}; DWORD length = 256;
  if (argc != 5 || std::wstring(argv[1]) != L"--isolated-synthetic-credentials" ||
      !GetUserNameW(user, &length) || std::wstring(user).find(L"AutofinanceTest_") != 0) {
    std::cerr << "Requires a disposable AutofinanceTest_* Windows user and three fixture EXEs.\n";
    return 77;
  }
  try {
    const auto root = Lower(TestRoot());
    for (int i = 2; i < 5; ++i)
      CHECK(Lower(argv[i]).find(root) == 0);
    WindowsSessionStore store;
    const auto source = store.inspect(argv[2]), destination = store.inspect(argv[3]),
               other = store.inspect(argv[4]);
    CHECK(source.key != destination.key && source.key != other.key && destination.key != other.key);
    CHECK(source.support == destination.support && destination.support == SupportDirectory());
    for (const auto* path : {&source, &destination, &other})
      CHECK(!store.id(path->key) && !store.journal(path->key));
    // The profile must be fresh. These synthetic sentinel files are never DBs
    // opened/copied by the installer service. No existing support is modified.
    CHECK(!std::filesystem::exists(source.support));
    const std::vector<std::wstring> files{L"sqlite\\autofinance.sqlite",
        L"sqlite\\autofinance.sqlite-wal", L"sqlite\\copies\\snapshot-test\\autofinance.sqlite",
        L"sqlite\\local-backups\\catalog-a.json",
        L"sqlite\\local-backups\\restore\\test\\journal.json", L"drive-sync\\state.json"};
    for (const auto& relative : files) {
      const auto path = std::filesystem::path(source.support) / relative;
      std::filesystem::create_directories(path.parent_path());
      std::ofstream output(path, std::ios::binary); output << "synthetic-financial-sentinel";
    }
    const auto sourceId = store.newId(), otherId = store.newId();
    Secret secret; secret.bytes = {1, 4, 7, 2, 8};
    store.setId(source.key, sourceId); store.write(sourceId, secret);
    store.setId(other.key, otherId); store.write(otherId, secret);
    SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::install, destination.exe, destination.version,
        destination.support, source.exe) == Status::ready);
    Confirmation consent;
    CHECK(service.prepareAdoption(consent) == Status::ready);
    CHECK(service.confirmAdoption(consent) == Status::committed);
    CHECK(!store.id(source.key) && !store.read(sourceId));
    const auto destinationId = store.id(destination.key);
    CHECK(destinationId && *destinationId != sourceId && store.read(*destinationId)->equals(secret));
    CHECK(service.finishMaintenance() == Status::ready);
    CHECK(service.prepareMaintenance(Action::repair, destination.exe, destination.version,
        destination.support) == Status::ready);
    CHECK(service.cleanupOwnSession() == Status::blocked);
    CHECK(store.id(destination.key) == destinationId && store.read(*destinationId)->equals(secret));
    CHECK(service.finishMaintenance() == Status::ready);
    CHECK(service.prepareMaintenance(Action::uninstall, destination.exe, destination.version,
        destination.support) == Status::ready);
    CHECK(service.cleanupOwnSession() == Status::cleared);
    CHECK(service.cleanupOwnSession() == Status::cleared);
    CHECK(!store.id(destination.key) && !store.read(*destinationId));
    CHECK(store.id(other.key) == otherId && store.read(otherId)->equals(secret));
    CHECK(service.finishMaintenance() == Status::ready);
    for (const auto& relative : files) {
      std::ifstream input(std::filesystem::path(source.support) / relative, std::ios::binary);
      const std::string value((std::istreambuf_iterator<char>(input)), {});
      CHECK(value == "synthetic-financial-sentinel");
    }
    // Only the explicit synthetic target created above, never enumerate targets.
    store.erase(otherId); CHECK(!store.read(otherId)); store.removeId(other.key);
    std::cout << "Native synthetic Credential Manager and preservation checks passed.\n";
    return 0;
  } catch (...) {
    // Leave disposable profile for diagnosis. Do not print OS errors or secrets.
    std::cerr << "Native synthetic test failed; discard the isolated profile after diagnosis.\n";
    return 1;
  }
}
