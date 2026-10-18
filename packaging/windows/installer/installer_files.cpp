#include "installer_files.h"
#include <bcrypt.h>
#include <algorithm>
#include <fstream>
#include <set>
#include <stdexcept>

namespace autofinance::installer {
namespace fs = std::filesystem;
namespace {
void Check(bool ok) { if (!ok) throw std::runtime_error("INSTALL-FILES"); }
std::wstring Lower(std::wstring text) {
  if (!text.empty()) CharLowerBuffW(text.data(), static_cast<DWORD>(text.size()));
  return text;
}
bool Exists(const fs::path& path) { return fs::exists(path); }
// Deliberately ASCII manifest: generated payload paths use UTF-8 only after a
// strict ASCII check. User/profile/source paths are always Unicode API strings.
std::string Narrow(const std::wstring& value) {
  Check(std::all_of(value.begin(), value.end(), [](wchar_t c) { return c >= 32 && c <= 126; }));
  std::string result;
  for (const auto c : value) result += static_cast<char>(c);
  return result;
}
std::wstring Wide(const std::string& value) {
  Check(std::all_of(value.begin(), value.end(), [](unsigned char c) { return c >= 32 && c <= 126; }));
  return std::wstring(value.begin(), value.end());
}
void Save(const fs::path& path, const Manifest& manifest, bool replace) {
  std::string bytes = "AutofinanceFilesV1\t" + Narrow(kAppId) + "\t" +
      Narrow(VersionText(manifest.version)) + "\n";
  for (const auto& file : manifest.files) bytes += Narrow(file.hash) + "\t" +
      std::to_string(file.size) + "\t" + Narrow(file.path) + "\n";
  HANDLE handle = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
      replace ? CREATE_ALWAYS : CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  Check(handle != INVALID_HANDLE_VALUE);
  DWORD written = 0;
  const bool ok = WriteFile(handle, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr)
      && written == bytes.size() && FlushFileBuffers(handle);
  CloseHandle(handle);
  // A reported write failure before publishing a new receipt has not changed
  // payload files. Retire only the CREATE_NEW file this call actually owned.
  if (!ok && !replace) DeleteFileW(path.c_str());
  Check(ok);
}
void Remove(const fs::path& path) {
  if (Exists(path)) Check(!!DeleteFileW(path.c_str()));
}
void EmptyParents(fs::path parent, const fs::path& stop) {
  while (parent != stop && parent.native().size() > stop.native().size()) {
    if (!RemoveDirectoryW(parent.c_str())) break;
    parent = parent.parent_path();
  }
}
}  // namespace
Version ParseVersion(const std::wstring& text, wchar_t separator) {
  Version result{};
  size_t offset = 0;
  for (size_t i = 0; i < 4; ++i) {
    const size_t end = text.find(i == 2 ? separator : L'.', offset);
    const auto part = text.substr(offset, end == std::wstring::npos ? end : end - offset);
    Check(!part.empty() && part.size() <= 5 && part.find_first_not_of(L"0123456789") == std::wstring::npos);
    result[i] = static_cast<unsigned>(std::stoul(part));
    Check(result[i] <= 65535 && (i != 3 || result[i] > 0));
    Check((i == 3) == (end == std::wstring::npos));
    offset = end + 1;
  }
  return result;
}
std::wstring VersionText(const Version& v) {
  return std::to_wstring(v[0]) + L"." + std::to_wstring(v[1]) + L"." +
      std::to_wstring(v[2]) + L"." + std::to_wstring(v[3]);
}
Manifest ReadManifest(const fs::path& path) {
  Check(fs::file_size(path) < 4 * 1024 * 1024);
  std::ifstream stream(path, std::ios::binary);
  std::string line;
  Check(!!std::getline(stream, line));
  const auto prefix = std::string("AutofinanceFilesV1\t") + Narrow(kAppId) + "\t";
  Check(line.rfind(prefix, 0) == 0);
  Manifest manifest{ParseVersion(Wide(line.substr(prefix.size()))), {}};
  std::set<std::wstring> names;
  while (std::getline(stream, line)) {
    const auto first = line.find('\t'), second = line.find('\t', first + 1);
    Check(first == 64 && second != std::string::npos);
    File file{Wide(line.substr(second + 1)), Wide(line.substr(0, first)), 0};
    const auto size = line.substr(first + 1, second - first - 1);
    Check(!size.empty() && size.size() <= 16 && size.find_first_not_of("0123456789") == std::string::npos);
    file.size = std::stoull(size);
    Check(file.hash.find_first_not_of(L"0123456789abcdef") == std::wstring::npos);
    ValidateFile(L"C:\\AutofinanceManifestValidation", file.path);
    Check(names.insert(Lower(file.path)).second && manifest.files.size() < 20000);
    manifest.files.push_back(std::move(file));
  }
  Check(stream.eof() && !manifest.files.empty());
  Check(names.count(L"myautofinance.exe") && names.count(L"installer/autofinance_setup_bridge.dll"));
  return manifest;
}
void ValidateRoot(const fs::path& root) {
  const auto text = root.native();
  Check(text.size() > 3 && text.size() < MAX_PATH && text[1] == L':' && text[2] == L'\\'
      && text.find(L':', 2) == std::wstring::npos && text.find(L'/') == std::wstring::npos
      && root.lexically_normal() == root);
  for (auto part = root; part.has_relative_path(); part = part.parent_path()) {
    const auto leaf = part.filename().native();
    Check(!leaf.empty() && leaf.back() != L'.' && leaf.back() != L' ');
    DWORD attrs = GetFileAttributesW(part.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES) Check(!(attrs & FILE_ATTRIBUTE_REPARSE_POINT));
    else Check(GetLastError() == ERROR_FILE_NOT_FOUND || GetLastError() == ERROR_PATH_NOT_FOUND);
  }
}
void ValidateFile(const fs::path& root, const std::wstring& relative) {
  Check(!relative.empty() && relative.size() < 220 && relative.find_first_of(L"\\:\t\r\n\"{};*") == std::wstring::npos);
  for (const auto c : relative) Check(c >= 32 && c < 127);
  const auto lowered = Lower(relative);
  Check(lowered.rfind(L".autofinance-", 0) != 0 && lowered.rfind(L"unins", 0) != 0);
  for (const auto* forbidden : {L"sqlite", L"drive-sync", L"local-backups", L"credentials", L"token", L"snapshot", L"diagnostics", L"client_secret"})
    Check(lowered.find(forbidden) == std::wstring::npos || lowered == L"sqlite3.dll");
  const auto extension = Lower(fs::path(relative).extension().native());
  for (const auto* forbidden : {L".db", L".csv", L".log", L".bak", L".key", L".pem", L".pfx", L".ps1", L".bat", L".cmd", L".iss"}) Check(extension != forbidden);
  size_t offset = 0;
  while (offset < relative.size()) {
    const auto end = relative.find(L'/', offset);
    const auto part = relative.substr(offset, end == std::wstring::npos ? end : end - offset);
    Check(!part.empty() && part != L"." && part != L".." && part.back() != L'.' && part.back() != L' ');
    const auto base = Lower(part.substr(0, part.find(L'.')));
    Check(base != L"con" && base != L"prn" && base != L"aux" && base != L"nul" &&
        !(base.size() == 4 && (base.rfind(L"com", 0) == 0 || base.rfind(L"lpt", 0) == 0) && base[3] >= L'1' && base[3] <= L'9'));
    if (end == std::wstring::npos) break;
    offset = end + 1;
    Check(offset < relative.size());
  }
  auto relativePath = fs::path(relative);
  relativePath.make_preferred();
  const auto full = root / relativePath;
  ValidateRoot(full);
  if (Exists(full)) {
    Check(fs::is_regular_file(full));
    HANDLE handle = CreateFileW(full.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(handle != INVALID_HANDLE_VALUE);
    BY_HANDLE_FILE_INFORMATION info{};
    const bool ok = GetFileInformationByHandle(handle, &info) && info.nNumberOfLinks == 1;
    CloseHandle(handle);
    Check(ok);
  }
}
std::wstring HashFile(const fs::path& path) {
  std::ifstream stream(path, std::ios::binary);
  Check(stream.good());
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  Check(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0);
  const auto created = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0);
  if (created != 0) { BCryptCloseAlgorithmProvider(algorithm, 0); Check(false); }
  std::array<char, 65536> bytes{};
  bool ok = true;
  while (stream) {
    stream.read(bytes.data(), bytes.size());
    const auto count = stream.gcount();
    if (count) ok = ok && BCryptHashData(hash, reinterpret_cast<PUCHAR>(bytes.data()), static_cast<ULONG>(count), 0) == 0;
  }
  BYTE digest[32]{};
  ok = ok && stream.eof() && BCryptFinishHash(hash, digest, sizeof(digest), 0) == 0;
  BCryptDestroyHash(hash); BCryptCloseAlgorithmProvider(algorithm, 0);
  Check(ok);
  std::wstring result;
  for (const BYTE b : digest) { result += L"0123456789abcdef"[b >> 4]; result += L"0123456789abcdef"[b & 15]; }
  return result;
}
void VerifyManifest(const fs::path& root, const Manifest& manifest) {
  for (const auto& file : manifest.files) {
    ValidateFile(root, file.path);
    Check(fs::file_size(root / file.path) == file.size && HashFile(root / file.path) == file.hash);
  }
}
void WriteReceipt(const fs::path& root, const Manifest& manifest) {
  ValidateRoot(root);
  const auto temporary = root / L".autofinance-pending-new";
  ValidateRoot(temporary);
  if (Exists(temporary)) {
    // A crash before the receipt rename cannot have modified payload files.
    // Validate the reserved file before retiring it; never truncate a receipt.
    Check(manifest.version >= ReadManifest(temporary).version);
    Remove(temporary);
  }
  Save(temporary, manifest, false);
  Check(!!MoveFileExW(temporary.c_str(), (root / kPending).c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH));
}
void PruneOwnedDirectories(const fs::path& root, const Manifest& manifest) {
  for (const auto& file : manifest.files) {
    ValidateFile(root, file.path);
    auto full = root / file.path;
    full.make_preferred();
    EmptyParents(full.parent_path(), root);
  }
}
Replacement::Replacement(fs::path root, Manifest incoming)
    : root_(std::move(root)), incoming_(std::move(incoming)) {}
Replacement::~Replacement() { release(); }
void Replacement::release() { for (auto h : pins_) CloseHandle(h); pins_.clear(); }
void Replacement::prepare() {
  Check(!started_);
  ValidateRoot(root_);
  const auto backup = root_ / kPrevious;
  ValidateRoot(backup);
  recovering_ = Exists(root_ / kPending) || Exists(root_ / L".autofinance-pending-new");
  Check(recovering_ || !Exists(backup));
  if (recovering_) {
    pending_ = ReadManifest(root_ / (Exists(root_ / kPending) ? kPending : L".autofinance-pending-new"));
    Check(incoming_.version >= pending_.version);
  }
  if (Exists(root_ / kManifest)) previous_ = ReadManifest(root_ / kManifest);
  else if (recovering_ && Exists(backup / kManifest)) previous_ = ReadManifest(backup / kManifest);
  else Check(!Exists(backup));
  std::set<std::wstring> allowed, names;
  for (const auto* manifest : {&previous_, &pending_}) for (const auto& file : manifest->files) allowed.insert(Lower(file.path));
  for (const auto* manifest : {&previous_, &pending_, &incoming_}) for (const auto& file : manifest->files) {
    ValidateFile(root_, file.path);
    if (Exists(root_ / file.path)) Check(allowed.count(Lower(file.path)) > 0);
    if (names.insert(Lower(file.path)).second) owned_.push_back(file.path);
  }
  // All lock failures occur before any file is renamed.
  for (const auto& path : owned_) if (Lower(path) != L"myautofinance.exe" && Exists(root_ / path)) {
    const auto h = CreateFileW((root_ / path).c_str(), GENERIC_READ | DELETE, FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(h != INVALID_HANDLE_VALUE);
    pins_.push_back(h);
  }
  // Durable high-water version. A retry cannot downgrade an interrupted package.
  // Save to a temporary owned name then replace, never truncate a live receipt.
  fs::create_directories(root_);
  auto receipt = incoming_;
  std::set<std::wstring> recorded;
  for (const auto& file : receipt.files) recorded.insert(Lower(file.path));
  for (const auto* manifest : {&previous_, &pending_}) for (const auto& file : manifest->files)
    if (recorded.insert(Lower(file.path)).second) receipt.files.push_back(file);
  WriteReceipt(root_, receipt);
  started_ = true;
  fs::create_directories(backup);
  if (!previous_.files.empty() && !Exists(backup / kManifest)) Save(backup / kManifest, previous_, false);
  for (const auto& path : owned_) if (Exists(root_ / path)) {
    fs::create_directories((backup / path).parent_path());
    ValidateFile(backup, path);
    Check(!!MoveFileExW((root_ / path).c_str(), (backup / path).c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH));
    moved_.push_back(path);
  }
}
void Replacement::verify() {
  Check(started_);
  ValidateRoot(root_ / kManifest);
  const auto installed = ReadManifest(root_ / kManifest);
  Check(installed.version == incoming_.version && installed.files.size() == incoming_.files.size());
  for (size_t i = 0; i < installed.files.size(); ++i) Check(installed.files[i].path == incoming_.files[i].path &&
      installed.files[i].hash == incoming_.files[i].hash && installed.files[i].size == incoming_.files[i].size);
  VerifyManifest(root_, incoming_);
  verified_ = true;
}
void Replacement::removeBackupFiles() {
  const auto backup = root_ / kPrevious;
  release();
  for (const auto& path : owned_) {
    ValidateFile(backup, path);
    Remove(backup / path);
    EmptyParents((backup / path).parent_path(), backup);
  }
  Remove(backup / kManifest);
  RemoveDirectoryW(backup.c_str());  // Unknown files are deliberately retained.
}
void Replacement::complete(bool keepReceipt) {
  Check(verified_);
  // After this boundary do not restore an older binary (adoption may commit).
  complete_ = true;
  removeBackupFiles();
  if (!keepReceipt) acknowledge();
}
void Replacement::acknowledge() {
  Check(complete_);
  RemoveDirectoryW((root_ / kPrevious).c_str());
  Remove(root_ / kPending);
}
bool Replacement::rollback() {
  release();
  if (!started_ || complete_) return true;
  try {
    for (const auto& file : incoming_.files) {
      ValidateFile(root_, file.path);
      // A file not yet moved may still be the original: never remove it.
      if (std::find(moved_.begin(), moved_.end(), file.path) != moved_.end() ||
          std::none_of(previous_.files.begin(), previous_.files.end(), [&](const File& f) { return f.path == file.path; })) Remove(root_ / file.path);
    }
    for (const auto& path : moved_) {
      Check(!Exists(root_ / path));
      Check(!!MoveFileExW((root_ / kPrevious / path).c_str(), (root_ / path).c_str(), MOVEFILE_WRITE_THROUGH));
    }
    if (!previous_.files.empty()) Save(root_ / kManifest, previous_, true);
    else Remove(root_ / kManifest);
    if (!recovering_) { removeBackupFiles(); Remove(root_ / kPending); }
    PruneOwnedDirectories(root_, incoming_);
    if (!recovering_ && previous_.files.empty()) RemoveDirectoryW(root_.c_str());
    started_ = false;
    return true;
  } catch (...) { return false; }
}
}  // namespace autofinance::installer
