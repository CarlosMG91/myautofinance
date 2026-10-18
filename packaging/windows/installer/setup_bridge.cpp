#include "installer_files.h"
#include "windows_session_store.h"
#include <shlobj.h>
#include <algorithm>
#include <memory>
#include <optional>

namespace af = autofinance::maintenance;
namespace files = autofinance::installer;
namespace fs = std::filesystem;
namespace {
constexpr wchar_t kUninstallKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{82D31B27-9717-4DB7-AB32-D098BF3C2859}_is1";
struct Context {
  af::WindowsSessionStore store;
  af::SessionMaintenance session{store};
  fs::path root, staged, manifestPath;
  files::Manifest manifest;
  std::wstring oldVersion, sourceInfo;
  af::Action action = af::Action::install;
  bool active = false, preparedAdoption = false, sealed = false, uninstall = false;
  af::Confirmation confirmation;
  std::unique_ptr<files::Replacement> replacement;
  std::vector<HANDLE> uninstallPins;
  ~Context() { for (auto h : uninstallPins) CloseHandle(h); }
};
std::unique_ptr<Context> context;
struct OlderPackage {};
void RejectOlder(const files::Version& incoming, const files::Version& installed) {
  if (incoming < installed) throw OlderPackage{};
}
void Require(bool value, af::Status status = af::Status::blocked) { if (!value) throw af::Error{status}; }
template <class F> int Result(F fn) noexcept {
  try { return static_cast<int>(fn()); }
  catch (const OlderPackage&) { return 9; }
  catch (const af::Error& error) { return static_cast<int>(error.status); }
  catch (...) { return static_cast<int>(af::Status::failed); }
}
std::wstring Lower(std::wstring s) {
  if (!s.empty()) CharLowerBuffW(s.data(), static_cast<DWORD>(s.size()));
  return s;
}
std::wstring Directory(std::wstring s) {
  while (!s.empty() && s.back() == L'\\') s.pop_back();
  return Lower(s);
}
fs::path FixedRoot() {
  PWSTR folder = nullptr;
  Require(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DONT_VERIFY, nullptr, &folder) == S_OK);
  const auto result = fs::path(folder) / L"Programs\\Autofinance";
  CoTaskMemFree(folder);
  files::ValidateRoot(result);
  return result;
}
std::optional<std::wstring> RegistryString(const wchar_t* name) {
  HKEY key = nullptr;
  const auto opened = RegOpenKeyExW(HKEY_CURRENT_USER, kUninstallKey, 0, KEY_READ | KEY_WOW64_64KEY, &key);
  if (opened == ERROR_FILE_NOT_FOUND) return {};
  Require(opened == ERROR_SUCCESS);
  wchar_t value[32768]{};
  DWORD size = sizeof(value), type = 0;
  const auto result = RegQueryValueExW(key, name, nullptr, &type, reinterpret_cast<BYTE*>(value), &size);
  RegCloseKey(key);
  Require(result == ERROR_SUCCESS && type == REG_SZ && size >= sizeof(wchar_t) &&
      size <= sizeof(value) && size % sizeof(wchar_t) == 0 && value[size / sizeof(wchar_t) - 1] == L'\0');
  return value;
}
void RejectMachineInstall() {
  for (const auto view : {KEY_WOW64_32KEY, KEY_WOW64_64KEY}) {
    HKEY key = nullptr;
    const auto opened = RegOpenKeyExW(HKEY_LOCAL_MACHINE, kUninstallKey, 0, KEY_READ | view, &key);
    if (key) RegCloseKey(key);
    Require(opened == ERROR_FILE_NOT_FOUND);
  }
}
void Assess(Context& c) {
  RejectMachineInstall();
  c.root = FixedRoot();
  const auto location = RegistryString(L"InstallLocation");
  const auto display = RegistryString(L"DisplayVersion");
  Require(location.has_value() == display.has_value());
  std::optional<files::Version> registered;
  if (location) {
    Require(Directory(*location) == Directory(c.root.native()));
    registered = files::ParseVersion(*display, L'+');
    RejectOlder(c.manifest.version, *registered);
    c.oldVersion = files::VersionText(*registered);
  }
  const bool recovering = fs::exists(c.root / files::kPending) || fs::exists(c.root / L".autofinance-pending-new");
  if (recovering) {
    const auto path = c.root / (fs::exists(c.root / files::kPending) ? files::kPending : L".autofinance-pending-new");
    files::ValidateRoot(path);
    const auto receipt = files::ReadManifest(path);
    RejectOlder(c.manifest.version, receipt.version);
  }
  const auto exe = c.root / L"myautofinance.exe";
  if (fs::exists(exe)) {
    Require(registered || recovering);
    const auto actual = c.store.inspect(exe.native());
    RejectOlder(c.manifest.version, actual.version);
    if (!recovering) Require(registered == actual.version);
    c.oldVersion = files::VersionText(actual.version);
    c.action = recovering ? af::Action::install :
        (c.manifest.version == actual.version ? af::Action::repair : af::Action::update);
  } else {
    Require(!registered || recovering);
    c.action = af::Action::install;
  }
  if (registered && !recovering) Require(fs::exists(c.root / files::kManifest));
  if (!registered && !recovering && fs::exists(c.root)) Require(fs::is_empty(c.root));
  if (fs::exists(c.root / files::kManifest)) {
    files::ValidateRoot(c.root / files::kManifest);
    const auto installed = files::ReadManifest(c.root / files::kManifest);
    if (!recovering) Require(registered && installed.version == *registered);
  }
}
Context& Current() { Require(!!context); return *context; }
void CopyText(const std::wstring& text, wchar_t* buffer, unsigned capacity) {
  Require(buffer && capacity > text.size() && capacity <= 32768);
  std::copy(text.begin(), text.end(), buffer); buffer[text.size()] = L'\0';
}
}  // namespace

// Integer results are maintenance::Status (0..8), plus 9 = older package. No ABI
// contains a credential, account, token, capability, arbitrary registry key or
// arbitrary destination. One Inno process/thread owns the whole operation.
extern "C" int __stdcall AfInitialize(const wchar_t* manifest, const wchar_t* staged) noexcept {
  return Result([&] {
    Require(manifest && staged && (!context || !context->active));
    auto c = std::make_unique<Context>();
    c->manifestPath = manifest; c->staged = staged;
    c->manifest = files::ReadManifest(c->manifestPath);
    const auto candidate = c->store.inspect(c->staged.native());
    Require(candidate.version == c->manifest.version && candidate.support == af::SupportDirectory());
    const auto found = std::find_if(c->manifest.files.begin(), c->manifest.files.end(),
        [](const files::File& file) { return file.path == L"myautofinance.exe"; });
    Require(found != c->manifest.files.end() && found->hash == files::HashFile(c->staged));
    Assess(*c);
    context = std::move(c);
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfInfo(unsigned field, wchar_t* buffer, unsigned capacity) noexcept {
  return Result([&] {
    const auto& c = Current();
    std::wstring result;
    switch (field) {
      case 0: result = c.root.native(); break;
      case 1: result = af::SupportDirectory(); break;
      case 2: result = c.oldVersion; break;
      case 3: result = c.action == af::Action::install ? L"install" :
          c.action == af::Action::update ? L"update" : L"repair"; break;
      default: Require(false);
    }
    CopyText(result, buffer, capacity);
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfSource(const wchar_t* source, wchar_t* buffer, unsigned capacity) noexcept {
  return Result([&] {
    auto& c = Current();
    Require(source && c.action == af::Action::install && !c.active);
    af::Inspection inspected;
    const auto status = c.session.inspectInstallation(source, inspected);
    Require(status == af::Status::ready, status);
    Require(inspected.installation.key != af::DirectoryKey((c.root / L"myautofinance.exe").native()) &&
        inspected.installation.support == af::SupportDirectory() &&
        ((inspected.identity && inspected.hasSession) || inspected.recoveryPending), af::Status::conflict);
    c.sourceInfo = files::VersionText(inspected.installation.version) + L"\r\nIdentificador local: " +
        inspected.identity.value_or(L"recuperación pendiente");
    CopyText(c.sourceInfo, buffer, capacity);
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfBegin(const wchar_t* source) noexcept {
  return Result([&] {
    auto& c = Current();
    Require(!c.active);
    // An empty Pascal/Delphi string may cross the C ABI as nullptr. Absence of
    // the optional source always means no adoption, never an implicit source.
    const std::wstring selected = source ? source : L"";
    Assess(c);
    const auto status = c.session.prepareMaintenance(c.action,
        (c.root / L"myautofinance.exe").native(), c.manifest.version,
        af::SupportDirectory(), selected, c.staged.native());
    Require(status == af::Status::ready, status);
    c.active = true;
    // Revalidate registry under the lease as well as the PE and source in T03.
    Assess(c);
    if (!selected.empty()) {
      const auto adoption = c.session.prepareAdoption(c.confirmation);
      Require(adoption == af::Status::ready, adoption);
      c.preparedAdoption = true;
    }
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfStage() noexcept {
  return Result([&] {
    auto& c = Current(); Require(c.active && !c.replacement && !c.uninstall);
    const auto quiet = c.session.requestClose(); Require(quiet == af::Status::closed, quiet);
    Assess(c);
    c.replacement = std::make_unique<files::Replacement>(c.root, c.manifest);
    c.replacement->prepare();
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfCommit() noexcept {
  return Result([&] {
    auto& c = Current(); Require(c.active && !!c.replacement && !c.uninstall);
    // Inno has already committed its registration at ssPostInstall. Do not
    // restore old files under new registration if verification now fails.
    c.sealed = true; c.replacement->seal();
    c.replacement->verify();
    const auto quiet = c.session.requestClose(); Require(quiet == af::Status::closed, quiet);
    // A post-copy failure must be reported as incomplete, never roll back a
    // possibly committed adoption or enable an older binary/schema combination.
    if (c.preparedAdoption) {
      const auto adopted = c.session.confirmAdoption(c.confirmation);
      Require(adopted == af::Status::committed, adopted);
    }
    c.replacement->complete(true);
    const auto status = c.session.finishMaintenance(); c.active = false;
    Require(status == af::Status::ready, status);
    c.replacement->acknowledge();
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfAbort() noexcept {
  return Result([&] {
    if (!context) return af::Status::cancelled;
    auto& c = *context;
    bool restored = !c.replacement || c.replacement->rollback();
    auto status = c.active ? c.session.abortMaintenance() : af::Status::cancelled;
    c.active = false;
    if (!restored || c.sealed) status = af::Status::blocked;
    context.reset();
    return status;
  });
}
extern "C" int __stdcall AfUninstallBegin(const wchar_t* root) noexcept {
  return Result([&] {
    Require(root && (!context || !context->active));
    auto c = std::make_unique<Context>();
    c->root = FixedRoot();
    Require(Directory(root) == Directory(c->root.native()));
    c->manifest = files::ReadManifest(c->root / files::kManifest);
    Assess(*c);
    Require(!fs::exists(c->root / files::kPending) && !fs::exists(c->root / L".autofinance-pending-new"));
    c->action = af::Action::uninstall; c->uninstall = true;
    const auto status = c->session.prepareMaintenance(af::Action::uninstall,
        (c->root / L"myautofinance.exe").native(), c->manifest.version, af::SupportDirectory());
    Require(status == af::Status::ready, status);
    c->active = true;
    for (const auto& file : c->manifest.files) {
      files::ValidateFile(c->root, file.path);
      if (file.path == L"myautofinance.exe" || !fs::exists(c->root / file.path)) continue;
      const auto handle = CreateFileW((c->root / file.path).c_str(), GENERIC_READ | DELETE,
          FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
      Require(handle != INVALID_HANDLE_VALUE, af::Status::busy);
      c->uninstallPins.push_back(handle);
    }
    context = std::move(c);
    return af::Status::ready;
  });
}
extern "C" int __stdcall AfUninstallClean() noexcept {
  return Result([&] {
    auto& c = Current(); Require(c.active && c.uninstall);
    const auto quiet = c.session.requestClose(); Require(quiet == af::Status::closed, quiet);
    files::WriteReceipt(c.root, c.manifest);
    return c.session.cleanupOwnSession();
  });
}
extern "C" int __stdcall AfUninstallFinish() noexcept {
  return Result([&] {
    auto& c = Current(); Require(c.active && c.uninstall);
    for (auto h : c.uninstallPins) CloseHandle(h);
    c.uninstallPins.clear();
    const auto status = c.session.finishMaintenance(); c.active = false;
    Require(status == af::Status::ready, status);
    for (const auto& file : c.manifest.files) Require(!fs::exists(c.root / file.path), af::Status::failed);
    Require(!fs::exists(c.root / files::kManifest), af::Status::failed);
    files::PruneOwnedDirectories(c.root, c.manifest);
    Require(!!DeleteFileW((c.root / files::kPending).c_str()), af::Status::failed);
    RemoveDirectoryW(c.root.c_str());  // Only if empty; unknown files stay.
    return af::Status::ready;
  });
}
