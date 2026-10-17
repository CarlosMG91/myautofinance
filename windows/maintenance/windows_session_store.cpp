#include "windows_session_store.h"

#include <windows.h>
#include <bcrypt.h>
#include <objbase.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <wincred.h>
#include <algorithm>
#include <cstring>
#include <filesystem>
#include <map>
#include <set>

namespace autofinance::maintenance {
struct NativePins {
  struct Pin { HANDLE handle; Installation metadata; BY_HANDLE_FILE_INFORMATION info; };
  std::map<std::wstring, Pin> files;
  ~NativePins() { for (const auto& entry : files) CloseHandle(entry.second.handle); }
};
namespace {
constexpr wchar_t kRoot[] = L"Software\\CarlosMG91\\Autofinance\\Installations\\";
void Check(bool value, Status status = Status::failed) {
  if (!value) throw Error{status};
}
struct Handle {
  HANDLE value = INVALID_HANDLE_VALUE;
  explicit Handle(HANDLE v) : value(v) {}
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
struct Key {
  HKEY value = nullptr;
  ~Key() { if (value) RegCloseKey(value); }
};
struct Credential {
  PCREDENTIALW value = nullptr;
  ~Credential() {
    if (value) {
      if (value->CredentialBlob) SecureZeroMemory(value->CredentialBlob,
                                                 value->CredentialBlobSize);
      CredFree(value);
    }
  }
};
std::wstring Lower(std::wstring text) {
  Check(!text.empty() && !!CharLowerBuffW(text.data(), static_cast<DWORD>(text.size())));
  return text;
}
bool Guid(const std::wstring& id) {
  GUID value{};
  return id.size() == 38 && id.front() == L'{' && id.back() == L'}' &&
      CLSIDFromString(id.c_str(), &value) == S_OK;
}
void HashKey(const std::wstring& key) {
  Check(key.size() == 64 && key.find_first_not_of(L"0123456789abcdef") ==
      std::wstring::npos, Status::blocked);
}
std::wstring Target(const std::wstring& id) {
  Check(Guid(id), Status::blocked);
  return L"Autofinance/Drive/" + id;
}
std::wstring RegistryPath(const std::wstring& key) {
  HashKey(key);
  return kRoot + key;
}
bool Open(Key& key, const std::wstring& hash, REGSAM access, bool create = false) {
  // RegFlushKey requires KEY_QUERY_VALUE, including for handles used to write.
  access |= KEY_QUERY_VALUE;
  const auto path = RegistryPath(hash);
  const auto result = create
      ? RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, access,
                       nullptr, &key.value, nullptr)
      : RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, access, &key.value);
  if (result == ERROR_FILE_NOT_FOUND && !create) return false;
  Check(result == ERROR_SUCCESS);
  return true;
}
void Flush(Key& key) { Check(RegFlushKey(key.value) == ERROR_SUCCESS); }
void DeleteEmpty(const std::wstring& hash) {
  Key key;
  if (!Open(key, hash, KEY_QUERY_VALUE)) return;
  DWORD subkeys = 0, values = 0;
  Check(RegQueryInfoKeyW(key.value, nullptr, nullptr, nullptr, &subkeys, nullptr,
      nullptr, &values, nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS);
  if (!subkeys && !values) {
    const auto result = RegDeleteKeyW(HKEY_CURRENT_USER, RegistryPath(hash).c_str());
    Check(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
  }
}
std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR raw = nullptr;
  Check(SHGetKnownFolderPath(id, KF_FLAG_DONT_VERIFY, nullptr, &raw) == S_OK);
  std::wstring result(raw);
  CoTaskMemFree(raw);
  return result;
}
// Reject aliases, reparse points, UNC, ADS and dot segments. Do not silently
// change the directory that participates in the pre-existing hash algorithm.
std::wstring ExactPath(const std::wstring& input, bool allowMissing) {
  // path_provider_windows 2.3.0 reads its module name with MAX_PATH + 1.
  // Reject longer executable paths before its truncation/fallback can change S.
  Check(input.size() > 3 && input.size() < MAX_PATH && input[1] == L':' &&
      input[2] == L'\\' && input.find(L':', 2) == std::wstring::npos &&
      input.find(L'/') == std::wstring::npos && input.find(L'\0') == std::wstring::npos,
      Status::blocked);
  std::vector<wchar_t> full(32768);
  auto length = GetFullPathNameW(input.c_str(), static_cast<DWORD>(full.size()),
                                 full.data(), nullptr);
  Check(length && length < full.size() &&
      Lower(input) == Lower(std::wstring(full.data(), length)), Status::blocked);
  std::filesystem::path path(input);
  for (auto part = path; part.has_relative_path(); part = part.parent_path()) {
    const auto leaf = part.filename().wstring();
    Check(!leaf.empty() && leaf.back() != L'.' && leaf.back() != L' ', Status::blocked);
    const DWORD attributes = GetFileAttributesW(part.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      Check(allowMissing && (GetLastError() == ERROR_FILE_NOT_FOUND ||
            GetLastError() == ERROR_PATH_NOT_FOUND), Status::blocked);
    } else Check(!(attributes & FILE_ATTRIBUTE_REPARSE_POINT), Status::blocked);
  }
  if (!allowMissing) {
    Handle file(CreateFileW(input.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    Check(file.value != INVALID_HANDLE_VALUE, Status::blocked);
    BY_HANDLE_FILE_INFORMATION info{};
    Check(GetFileInformationByHandle(file.value, &info) && info.nNumberOfLinks == 1,
          Status::blocked);
    length = GetFinalPathNameByHandleW(file.value, full.data(),
        static_cast<DWORD>(full.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    Check(length > 4 && length < full.size() &&
        Lower(std::wstring(full.data() + 4, length - 4)) == Lower(input), Status::blocked);
  }
  Check(Lower(path.filename().wstring()) == L"myautofinance.exe", Status::blocked);
  return input;
}
std::wstring LockPath(const std::wstring& hash) {
  HashKey(hash);
  const auto root = KnownFolder(FOLDERID_LocalAppData) +
      L"\\com.carlosmg91\\Autofinance\\maintenance";
  std::error_code error;
  std::filesystem::create_directories(root, error);
  Check(!error);
  // No lock files or financial files are removed, including at uninstall.
  return root + L"\\" + hash + L".lock";
}
struct WindowsLease final : Lease {
  std::vector<HANDLE> handles;
  std::shared_ptr<NativePins> pins;
  ~WindowsLease() override { for (auto h : handles) CloseHandle(h); }
};
std::unique_ptr<Lease> Acquire(const std::vector<std::wstring>& keys, bool shared) {
  auto lease = std::make_unique<WindowsLease>();
  const std::set<std::wstring> ordered(keys.begin(), keys.end());
  for (const auto& hash : ordered) {
    const auto path = LockPath(hash);
    const auto h = CreateFileW(path.c_str(), GENERIC_READ | (shared ? 0 : GENERIC_WRITE),
        shared ? FILE_SHARE_READ : 0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(h != INVALID_HANDLE_VALUE, GetLastError() == ERROR_SHARING_VIOLATION
        ? Status::busy : Status::failed);
    lease->handles.push_back(h);
  }
  return lease;
}
struct JournalRecord {
  DWORD version, phase, hadDestination;
  wchar_t sourceKey[65], sourceId[39], destinationKey[65], destinationId[39];
};
std::wstring Field(const wchar_t* field, size_t length) {
  Check(field[length - 1] == L'\0', Status::blocked);
  Check(wcsnlen(field, length) == length - 1, Status::blocked);
  return std::wstring(field, length - 1);
}
}  // namespace

std::wstring CurrentExecutable() {
  std::vector<wchar_t> path(32768);
  const auto length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  Check(length && length < path.size());
  return std::wstring(path.data(), length);
}
std::wstring SupportDirectory() {
  return KnownFolder(FOLDERID_RoamingAppData) + L"\\com.carlosmg91\\Autofinance";
}
std::wstring DirectoryKey(const std::wstring& exe) {
  auto directory = Lower(exe.substr(0, exe.find_last_of(L"\\/")));
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  Check(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0);
  BYTE digest[32]{};
  const auto result = BCryptHash(algorithm, nullptr, 0,
      reinterpret_cast<PUCHAR>(directory.data()),
      static_cast<ULONG>(directory.size() * sizeof(wchar_t)), digest, sizeof(digest));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  Check(result == 0);
  std::wstring key;
  for (const BYTE byte : digest) {
    key += L"0123456789abcdef"[byte >> 4];
    key += L"0123456789abcdef"[byte & 15];
  }
  return key;
}
Installation WindowsSessionStore::inspect(const std::wstring& input) {
  if (const auto pins = pins_.lock()) {
    const auto found = pins->files.find(Lower(input));
    if (found != pins->files.end()) {
      Handle probe(CreateFileW(input.c_str(), 0,
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      BY_HANDLE_FILE_INFORMATION info{};
      Check(probe.value != INVALID_HANDLE_VALUE &&
          GetFileInformationByHandle(probe.value, &info), Status::blocked);
      const auto& original = found->second.info;
      if (info.dwVolumeSerialNumber == original.dwVolumeSerialNumber &&
          info.nFileIndexHigh == original.nFileIndexHigh &&
          info.nFileIndexLow == original.nFileIndexLow) return found->second.metadata;
      // Destination was replaced under the operation's lease: inspect new PE.
    }
  }
  const auto exe = ExactPath(input, false);
  DWORD ignored = 0;
  const auto size = GetFileVersionInfoSizeW(exe.c_str(), &ignored);
  Check(size > 0, Status::blocked);
  std::vector<BYTE> data(size);
  Check(!!GetFileVersionInfoW(exe.c_str(), 0, size, data.data()), Status::blocked);
  for (const auto& field : std::vector<std::pair<std::wstring, std::wstring>>{
      {L"CompanyName", L"com.carlosmg91"}, {L"ProductName", L"Autofinance"},
      {L"InternalName", L"myautofinance"}, {L"OriginalFilename", L"myautofinance.exe"}}) {
    LPVOID value = nullptr;
    UINT length = 0;
    const auto query = L"\\StringFileInfo\\040904e4\\" + field.first;
    Check(VerQueryValueW(data.data(), query.c_str(), &value, &length) && length > 0 &&
        static_cast<wchar_t*>(value)[length - 1] == L'\0' &&
        std::wstring(static_cast<wchar_t*>(value), length - 1) == field.second, Status::blocked);
  }
  VS_FIXEDFILEINFO* info = nullptr;
  UINT length = 0;
  Check(VerQueryValueW(data.data(), L"\\", reinterpret_cast<LPVOID*>(&info), &length) &&
      length == sizeof(VS_FIXEDFILEINFO) && info->dwSignature == 0xfeef04bd &&
      info->dwFileVersionMS == info->dwProductVersionMS &&
      info->dwFileVersionLS == info->dwProductVersionLS, Status::blocked);
  // Inspect headers without executing the EXE or loading arbitrary libraries.
  Handle file(CreateFileW(exe.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  IMAGE_DOS_HEADER dos{};
  DWORD read = 0;
  Check(ReadFile(file.value, &dos, sizeof(dos), &read, nullptr) && read == sizeof(dos) &&
      dos.e_magic == IMAGE_DOS_SIGNATURE && dos.e_lfanew > 0, Status::blocked);
  LARGE_INTEGER offset{}; offset.QuadPart = dos.e_lfanew;
  Check(!!SetFilePointerEx(file.value, offset, nullptr, FILE_BEGIN), Status::blocked);
  IMAGE_NT_HEADERS64 pe{};
  Check(ReadFile(file.value, &pe, sizeof(pe), &read, nullptr) && read == sizeof(pe) &&
      pe.Signature == IMAGE_NT_SIGNATURE && pe.FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64 &&
      pe.OptionalHeader.Magic == IMAGE_NT_OPTIONAL_HDR64_MAGIC, Status::blocked);
  return {exe, DirectoryKey(exe), SupportDirectory(),
      {HIWORD(info->dwFileVersionMS), LOWORD(info->dwFileVersionMS),
       HIWORD(info->dwFileVersionLS), LOWORD(info->dwFileVersionLS)}};
}
Installation WindowsSessionStore::plan(const std::wstring& input, const std::wstring& staged) {
  const auto exe = ExactPath(input, true);
  if (GetFileAttributesW(exe.c_str()) != INVALID_FILE_ATTRIBUTES) return inspect(exe);
  auto result = inspect(staged);
  result.exe = exe;
  result.key = DirectoryKey(exe);
  return result;
}
std::wstring WindowsSessionStore::newId() {
  GUID guid{}; wchar_t id[39]{};
  Check(CoCreateGuid(&guid) == S_OK && StringFromGUID2(guid, id, 39) == 39);
  return id;
}
std::unique_ptr<Lease> WindowsSessionStore::lock(const std::vector<Installation>& paths) {
  std::vector<std::wstring> keys;
  for (const auto& path : paths) keys.push_back(path.key);
  auto base = Acquire(keys, false);
  auto* lease = static_cast<WindowsLease*>(base.get());
  lease->pins = std::make_shared<NativePins>();
  for (size_t i = 0; i < paths.size(); ++i) {
    const auto& path = paths[i];
    if (GetFileAttributesW(path.exe.c_str()) == INVALID_FILE_ATTRIBUTES) {
      Check(i == 0 && (GetLastError() == ERROR_FILE_NOT_FOUND ||
            GetLastError() == ERROR_PATH_NOT_FOUND), Status::blocked);
      continue;
    }
    const auto metadata = inspect(path.exe);
    // Deny read/execute/write even to legacy runners that lack the new gate.
    // Destination may be renamed by T05, then replaced; source stays immovable.
    const auto h = CreateFileW(path.exe.c_str(), GENERIC_READ,
        i == 0 ? FILE_SHARE_DELETE : 0, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    Check(h != INVALID_HANDLE_VALUE, Status::busy);
    BY_HANDLE_FILE_INFORMATION info{};
    if (!GetFileInformationByHandle(h, &info)) { CloseHandle(h); throw Error{Status::failed}; }
    lease->pins->files.emplace(Lower(path.exe), NativePins::Pin{h, metadata, info});
  }
  pins_ = lease->pins;
  return base;
}
bool WindowsSessionStore::running(const Installation& path) {
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  Check(snapshot.value != INVALID_HANDLE_VALUE);
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  Check(!!Process32FirstW(snapshot.value, &entry));
  do {
    // Same-user legacy runners do not yet hold the new lease. Fail closed if
    // a matching executable name cannot be inspected; never terminate it.
    if (Lower(entry.szExeFile) != L"myautofinance.exe") continue;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID));
    if (!process.value) {
      if (GetLastError() == ERROR_INVALID_PARAMETER) continue;  // exited
      throw Error{Status::busy};
    }
    std::vector<wchar_t> name(32768); DWORD length = static_cast<DWORD>(name.size());
    Check(!!QueryFullProcessImageNameW(process.value, 0, name.data(), &length), Status::busy);
    if (DirectoryKey(std::wstring(name.data(), length)) == path.key) return true;
  } while (Process32NextW(snapshot.value, &entry));
  Check(GetLastError() == ERROR_NO_MORE_FILES);
  return false;
}
std::optional<std::wstring> WindowsSessionStore::id(const std::wstring& hash) {
  Key key;
  if (!Open(key, hash, KEY_QUERY_VALUE)) return {};
  wchar_t value[39]{}; DWORD type = 0, size = sizeof(value);
  const auto result = RegQueryValueExW(key.value, L"Id", nullptr, &type,
      reinterpret_cast<LPBYTE>(value), &size);
  if (result == ERROR_FILE_NOT_FOUND) return {};
  Check(result == ERROR_SUCCESS && type == REG_SZ && size == sizeof(value) &&
      value[38] == L'\0' && Guid(value), Status::blocked);
  return value;
}
void WindowsSessionStore::setId(const std::wstring& hash, const std::wstring& value) {
  Check(Guid(value), Status::blocked);
  const auto previous = id(hash);
  Check(!previous || *previous == value, Status::conflict);
  Key key; Open(key, hash, KEY_SET_VALUE, true);
  Check(RegSetValueExW(key.value, L"Id", 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
  Flush(key);
}
void WindowsSessionStore::removeId(const std::wstring& hash) {
  Key key;
  if (!Open(key, hash, KEY_SET_VALUE)) return;
  const auto result = RegDeleteValueW(key.value, L"Id");
  Check(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
  Flush(key);
  // Delete only an empty own key; never recurse into another installation/journal.
  DeleteEmpty(hash);
}
std::unique_ptr<Secret> WindowsSessionStore::read(const std::wstring& id) {
  Credential credential;
  if (!CredReadW(Target(id).c_str(), CRED_TYPE_GENERIC, 0, &credential.value)) {
    Check(GetLastError() == ERROR_NOT_FOUND);
    return {};
  }
  Check(credential.value->Persist == CRED_PERSIST_LOCAL_MACHINE &&
      credential.value->CredentialBlobSize > 0 &&
      credential.value->CredentialBlobSize <= CRED_MAX_CREDENTIAL_BLOB_SIZE);
  auto secret = std::make_unique<Secret>();
  secret->bytes.assign(credential.value->CredentialBlob,
      credential.value->CredentialBlob + credential.value->CredentialBlobSize);
  return secret;
}
void WindowsSessionStore::write(const std::wstring& id, const Secret& secret) {
  Check(!secret.bytes.empty() && secret.bytes.size() <= CRED_MAX_CREDENTIAL_BLOB_SIZE);
  auto target = Target(id);
  CREDENTIALW value{};
  value.Type = CRED_TYPE_GENERIC; value.TargetName = target.data();
  value.Persist = CRED_PERSIST_LOCAL_MACHINE;
  value.CredentialBlobSize = static_cast<DWORD>(secret.bytes.size());
  value.CredentialBlob = const_cast<LPBYTE>(secret.bytes.data());
  Check(!!CredWriteW(&value, 0));
}
void WindowsSessionStore::erase(const std::wstring& id) {
  Check(CredDeleteW(Target(id).c_str(), CRED_TYPE_GENERIC, 0) || GetLastError() == ERROR_NOT_FOUND);
}
std::optional<Journal> WindowsSessionStore::journal(const std::wstring& hash) {
  Key key;
  if (!Open(key, hash, KEY_QUERY_VALUE)) return {};
  JournalRecord record{}; DWORD size = sizeof(record), type = 0;
  const auto result = RegQueryValueExW(key.value, L"AdoptionV1", nullptr, &type,
      reinterpret_cast<LPBYTE>(&record), &size);
  if (result == ERROR_FILE_NOT_FOUND) {
    wchar_t destination[65]{};
    size = sizeof(destination); type = 0;
    const auto link = RegQueryValueExW(key.value, L"AdoptionDestinationV1", nullptr,
        &type, reinterpret_cast<LPBYTE>(destination), &size);
    if (link == ERROR_FILE_NOT_FOUND) return {};
    Check(link == ERROR_SUCCESS && type == REG_SZ && size == sizeof(destination), Status::blocked);
    const auto target = Field(destination, 65);
    HashKey(target);
    Check(target != hash, Status::blocked);
    // Read directly, without following further links from an invalid record.
    Key destinationKey;
    Check(Open(destinationKey, target, KEY_QUERY_VALUE), Status::blocked);
    size = sizeof(record); type = 0;
    Check(RegQueryValueExW(destinationKey.value, L"AdoptionV1", nullptr, &type,
        reinterpret_cast<LPBYTE>(&record), &size) == ERROR_SUCCESS &&
        type == REG_BINARY && size == sizeof(record) && record.version == 1 &&
        record.phase <= 1 && record.hadDestination <= 1, Status::blocked);
    Journal j{Field(record.sourceKey, 65), Field(record.sourceId, 39),
        Field(record.destinationKey, 65), Field(record.destinationId, 39),
        record.hadDestination != 0, static_cast<Phase>(record.phase)};
    Check(j.sourceKey == hash && j.destinationKey == target && Guid(j.sourceId) &&
        Guid(j.destinationId) && j.sourceId != j.destinationId, Status::blocked);
    return j;
  }
  Check(result == ERROR_SUCCESS && type == REG_BINARY && size == sizeof(record) &&
      record.version == 1 && record.phase <= 1 && record.hadDestination <= 1, Status::blocked);
  Journal j{Field(record.sourceKey, 65), Field(record.sourceId, 39),
      Field(record.destinationKey, 65), Field(record.destinationId, 39),
      record.hadDestination != 0, static_cast<Phase>(record.phase)};
  HashKey(j.sourceKey); HashKey(j.destinationKey);
  Check(j.destinationKey == hash && j.sourceKey != hash && Guid(j.sourceId) &&
      Guid(j.destinationId) && j.sourceId != j.destinationId, Status::blocked);
  return j;
}
void WindowsSessionStore::save(const Journal& j) {
  HashKey(j.sourceKey); HashKey(j.destinationKey);
  Check(Guid(j.sourceId) && Guid(j.destinationId));
  JournalRecord record{};
  record.version = 1; record.phase = static_cast<DWORD>(j.phase);
  record.hadDestination = j.hadDestinationId ? 1 : 0;
  wcscpy_s(record.sourceKey, j.sourceKey.c_str());
  wcscpy_s(record.sourceId, j.sourceId.c_str());
  wcscpy_s(record.destinationKey, j.destinationKey.c_str());
  wcscpy_s(record.destinationId, j.destinationId.c_str());
  Key key; Open(key, j.destinationKey, KEY_SET_VALUE, true);
  Check(RegSetValueExW(key.value, L"AdoptionV1", 0, REG_BINARY,
      reinterpret_cast<const BYTE*>(&record), sizeof(record)) == ERROR_SUCCESS);
  Flush(key);
  // Reverse reservation blocks source startup too, without global discovery.
  Key source; Open(source, j.sourceKey, KEY_SET_VALUE, true);
  Check(RegSetValueExW(source.value, L"AdoptionDestinationV1", 0, REG_SZ,
      reinterpret_cast<const BYTE*>(j.destinationKey.c_str()),
      static_cast<DWORD>((j.destinationKey.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
  Flush(source);
}
void WindowsSessionStore::removeJournal(const std::wstring& hash) {
  const auto pending = journal(hash);
  if (pending) {
    Check(pending->destinationKey == hash, Status::blocked);
    Key source;
    if (Open(source, pending->sourceKey, KEY_SET_VALUE)) {
      const auto removed = RegDeleteValueW(source.value, L"AdoptionDestinationV1");
      Check(removed == ERROR_SUCCESS || removed == ERROR_FILE_NOT_FOUND);
      Flush(source);
    }
    DeleteEmpty(pending->sourceKey);
  }
  Key key;
  if (!Open(key, hash, KEY_SET_VALUE)) return;
  const auto result = RegDeleteValueW(key.value, L"AdoptionV1");
  Check(result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
  Flush(key);
  DeleteEmpty(hash);
}
std::unique_ptr<Lease> AcquireApplicationLease() {
  WindowsSessionStore store;
  const auto path = store.inspect(CurrentExecutable());
  auto lease = Acquire({path.key}, true);
  Check(!store.journal(path.key), Status::blocked);
  return lease;
}
}  // namespace autofinance::maintenance
