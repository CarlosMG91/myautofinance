#include "installer_files.h"
#include <fstream>
#include <iostream>
#include <functional>

namespace fs = std::filesystem;
using namespace autofinance::installer;
namespace {
void Check(bool value) { if (!value) throw std::runtime_error("test assertion"); }
void Put(const fs::path& path, const std::string& text) {
  fs::create_directories(path.parent_path());
  std::ofstream out(path, std::ios::binary); out << text; out.close(); Check(!out.fail());
}
std::string Get(const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(in), {}};
}
std::string Ascii(const std::wstring& text) {
  std::string result;
  for (const auto c : text) result += static_cast<char>(c);
  return result;
}
Manifest MakeManifest(const fs::path& source, Version version, const std::vector<std::wstring>& names) {
  Manifest result{version, {}};
  for (const auto& name : names) result.files.push_back({name, HashFile(source / name), fs::file_size(source / name)});
  return result;
}
void SaveManifest(const fs::path& path, const Manifest& manifest) {
  std::string text = "AutofinanceFilesV1\t" + Ascii(kAppId) + "\t" + Ascii(VersionText(manifest.version)) + "\n";
  for (const auto& file : manifest.files) text += Ascii(file.hash) + "\t" + std::to_string(file.size) + "\t" + Ascii(file.path) + "\n";
  Put(path, text);
}
void Throws(const std::function<void()>& operation) {
  bool caught = false; try { operation(); } catch (...) { caught = true; } Check(caught);
}
const std::vector<std::wstring> names{L"myautofinance.exe", L"installer/autofinance_setup_bridge.dll", L"data/app.so"};
void Fill(const fs::path& root, const std::string& version) {
  for (const auto& name : names) Put(root / name, version + Ascii(name));
}
void CopyPayload(const fs::path& from, const fs::path& to, const Manifest& manifest) {
  for (const auto& file : manifest.files) Put(to / file.path, Get(from / file.path));
  SaveManifest(to / kManifest, manifest);
}
}  // namespace
int main() {
  unsigned passed = 0;
  try {
    // CTest's working directory is the private build tree. Fresh, bounded
    // synthetic fixtures only; deliberately no recursive cleanup or HKCU access.
    const auto base = fs::current_path() / (L"fixtures-" + std::to_wstring(GetCurrentProcessId()));
    Check(!fs::exists(base)); fs::create_directory(base);
    const auto payload = base / L"payload";
    Fill(payload, "new");
    const auto incoming = MakeManifest(payload, {0, 1, 0, 2}, names);
    SaveManifest(payload / kManifest, incoming);
    Check(ReadManifest(payload / kManifest).files.size() == 3);
    passed = 1;
    Check(ParseVersion(L"1.10.0.1") > ParseVersion(L"1.2.9.9"));
    Check(ParseVersion(L"0.1.0+2", L'+') == incoming.version);
    for (const auto* invalid : {L"1.2.3", L"1.2.3.0", L"65536.0.0.1", L"1.2.3.4.5", L"1.2.3.-1", L"1.2.3+4"}) Throws([&] { ParseVersion(invalid); });
    ++passed;
    for (const auto* invalid : {L"../data", L"/root", L"C:/x", L"data//x", L"data/", L"data/a.", L"data/nul.txt", L"sqlite/a.sqlite", L"drive-sync/state.json", L"token.json", L".autofinance-files", L"data/*.dll"})
      Throws([&] { ValidateFile(base, invalid); });
    ++passed;
    const auto first = base / L"Primera instalación á";
    { Replacement operation(first, incoming); operation.prepare(); CopyPayload(payload, first, incoming); operation.verify(); operation.complete(); }
    VerifyManifest(first, incoming); Check(!fs::exists(first / kPending)); ++passed;

    const auto update = base / L"actualizar";
    Fill(update, "old"); Put(update / L"obsolete.dll", "old obsolete");
    auto oldNames = names; oldNames.push_back(L"obsolete.dll");
    const auto previous = MakeManifest(update, {0, 1, 0, 1}, oldNames);
    SaveManifest(update / kManifest, previous); Put(update / L"unknown.keep", "unowned");
    // An unrelated process retaining any owned DLL blocks before EXE rename.
    HANDLE blocked = CreateFileW((update / names[1]).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    Check(blocked != INVALID_HANDLE_VALUE);
    { Replacement operation(update, incoming); Throws([&] { operation.prepare(); }); }
    Check(fs::exists(update / names[0]) && !fs::exists(update / kPending)); CloseHandle(blocked); ++passed;
    // Simulates the T03 EXE pin: no read/write sharing, DELETE only.
    HANDLE exe = CreateFileW((update / names[0]).c_str(), GENERIC_READ, FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
    Check(exe != INVALID_HANDLE_VALUE);
    { Replacement operation(update, incoming); operation.prepare(); Check(!fs::exists(update / names[0])); Check(operation.rollback()); }
    CloseHandle(exe); VerifyManifest(update, previous); Check(Get(update / L"unknown.keep") == "unowned"); ++passed;
    // Cancellation/failed copy after partial extraction restores the prior files.
    { Replacement operation(update, incoming); operation.prepare(); Put(update / names[0], "partial"); Check(operation.rollback()); }
    VerifyManifest(update, previous); ++passed;
    // Repair accepts altered owned files; unknown colliding paths are rejected.
    Put(update / names[2], "damaged");
    { Replacement operation(update, incoming); operation.prepare(); CopyPayload(payload, update, incoming); operation.verify(); operation.complete(); }
    VerifyManifest(update, incoming); Check(!fs::exists(update / L"obsolete.dll"));
    Check(Get(update / L"unknown.keep") == "unowned"); ++passed;
    const auto collision = base / L"collision"; Put(collision / names[0], "foreign");
    { Replacement operation(collision, incoming); Throws([&] { operation.prepare(); }); }
    Check(Get(collision / names[0]) == "foreign"); ++passed;
    // Process loss keeps a durable high-water receipt and only owned backups.
    { Replacement operation(update, incoming); operation.prepare(); }
    Check(fs::exists(update / kPending) && !fs::exists(update / names[0]));
    auto downgrade = incoming; downgrade.version[3] = 1;
    { Replacement operation(update, downgrade); Throws([&] { operation.prepare(); }); }
    Check(fs::exists(update / kPending)); ++passed;
    { Replacement operation(update, incoming); operation.prepare(); CopyPayload(payload, update, incoming); operation.verify(); operation.complete(); }
    VerifyManifest(update, incoming); Check(!fs::exists(update / kPending)); ++passed;
    // Wrong post-copy hash cannot be reported as a successful installation.
    { Replacement operation(update, incoming); operation.prepare(); CopyPayload(payload, update, incoming); Put(update / names[0], "wrong"); Throws([&] { operation.verify(); }); Check(operation.rollback()); }
    VerifyManifest(update, incoming); ++passed;
    // A crash between flushing and renaming the receipt also permits repair.
    const auto early = base / L"early-crash";
    SaveManifest(early / L".autofinance-pending-new", incoming);
    { Replacement operation(early, incoming); operation.prepare(); CopyPayload(payload, early, incoming); operation.verify(); operation.complete(); }
    VerifyManifest(early, incoming); Check(!fs::exists(early / L".autofinance-pending-new")); ++passed;
    // Installed ownership metadata is verified too, not just application bytes.
    { Replacement operation(update, incoming); operation.prepare(); CopyPayload(payload, update, incoming);
      auto wrong = incoming; wrong.version[3] = 3; SaveManifest(update / kManifest, wrong);
      Throws([&] { operation.verify(); }); Check(operation.rollback()); }
    VerifyManifest(update, incoming); ++passed;
    // A file retired by a later interrupted package stays in the durable union,
    // even if the currently installed manifest disappeared during interruption.
    Put(payload / L"retired.dll", "intermediate");
    auto intermediateNames = names; intermediateNames.push_back(L"retired.dll");
    const auto intermediate = MakeManifest(payload, {0, 1, 0, 3}, intermediateNames);
    { Replacement operation(update, intermediate); operation.prepare(); CopyPayload(payload, update, intermediate); }
    fs::remove(update / kManifest);
    auto latest = incoming; latest.version[3] = 4;
    { Replacement operation(update, latest); operation.prepare(); }
    Check(ReadManifest(update / kPending).files.size() == 4);
    { Replacement operation(update, latest); operation.prepare(); CopyPayload(payload, update, latest); operation.verify(); operation.complete(); }
    Check(!fs::exists(update / L"retired.dll") && !fs::exists(update / kPrevious)); ++passed;
    // An arbitrary pre-existing recovery folder is never adopted or cleaned.
    const auto foreignBackup = base / L"foreign-backup";
    Put(foreignBackup / kPrevious / L"keep.txt", "unowned");
    { Replacement operation(foreignBackup, incoming); Throws([&] { operation.prepare(); }); }
    Check(Get(foreignBackup / kPrevious / L"keep.txt") == "unowned"); ++passed;
    // Initial cancellation leaves no empty owned tree to block a later install.
    const auto cancelled = base / L"initial-cancel";
    { Replacement operation(cancelled, incoming); operation.prepare(); CopyPayload(payload, cancelled, incoming); Check(operation.rollback()); }
    Check(!fs::exists(cancelled));
    { Replacement operation(cancelled, incoming); operation.prepare(); CopyPayload(payload, cancelled, incoming); operation.verify(); operation.complete(); }
    Put(cancelled / L"data/unknown.keep", "unowned");
    for (const auto& file : incoming.files) fs::remove(cancelled / file.path);
    PruneOwnedDirectories(cancelled, incoming);
    Check(!fs::exists(cancelled / L"installer") && Get(cancelled / L"data/unknown.keep") == "unowned"); ++passed;
    std::cout << passed << " installer file cases passed; synthetic files only, no credentials/registry\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << "installer file case failed after " << passed << ": " << e.what() << "\n"; return 1; }
}
