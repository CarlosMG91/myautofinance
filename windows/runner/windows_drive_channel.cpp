#include "windows_drive_channel.h"

#include <windows.h>
#include <wincred.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <objbase.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cstring>
#include <vector>

namespace {
std::wstring Wide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size == 0) return {};
  std::wstring result(size, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), size)) return {};
  return result;
}

// The executable directory identifies an installation; an unshared registry
// GUID prevents using another directory's credential, even after copying EXE.
std::wstring InstallationKey() {
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
      static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return {};
  std::wstring directory(path.data(), length);
  const auto separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return {};
  directory.resize(separator);
  if (!CharLowerBuffW(directory.data(), static_cast<DWORD>(directory.size()))) return {};
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM,
      nullptr, 0) != 0) return {};
  BYTE digest[32] = {};
  const NTSTATUS status = BCryptHash(algorithm, nullptr, 0,
      reinterpret_cast<PUCHAR>(directory.data()),
      static_cast<ULONG>(directory.size() * sizeof(wchar_t)), digest,
      static_cast<ULONG>(sizeof(digest)));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status != 0) return {};
  std::wstring key;
  constexpr wchar_t hex[] = L"0123456789abcdef";
  for (BYTE byte : digest) {
    key.push_back(hex[byte >> 4]);
    key.push_back(hex[byte & 15]);
  }
  return key;
}

void FreeCredential(PCREDENTIALW credential) {
  if (credential) {
    if (credential->CredentialBlob && credential->CredentialBlobSize) {
      SecureZeroMemory(credential->CredentialBlob, credential->CredentialBlobSize);
    }
    CredFree(credential);
  }
}
}  // namespace

bool WindowsDriveChannel::EnsureTarget() {
  if (!target_.empty()) return true;
  const std::wstring installation = InstallationKey();
  if (installation.empty()) return false;
  const std::wstring mutex_name = L"Local\\AutofinanceDrive-" + installation;
  HANDLE mutex = CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (!mutex) return false;
  const DWORD wait = WaitForSingleObject(mutex, 5000);
  if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
    CloseHandle(mutex);
    return false;
  }
  const std::wstring key_path =
      L"Software\\CarlosMG91\\Autofinance\\Installations\\" + installation;
  HKEY key = nullptr;
  bool success = false;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, nullptr,
      REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr,
      &key, nullptr) == ERROR_SUCCESS) {
    wchar_t id[39] = {};
    DWORD size = sizeof(id);
    DWORD type = 0;
    const LSTATUS read = RegQueryValueExW(key, L"Id", nullptr, &type,
        reinterpret_cast<LPBYTE>(id), &size);
    GUID guid;
    if (read == ERROR_FILE_NOT_FOUND) {
      if (CoCreateGuid(&guid) == S_OK && StringFromGUID2(guid, id, 39) == 39) {
        success = RegSetValueExW(key, L"Id", 0, REG_SZ,
            reinterpret_cast<const BYTE*>(id), sizeof(id)) == ERROR_SUCCESS;
      }
    } else {
      success = read == ERROR_SUCCESS && type == REG_SZ && size == sizeof(id) &&
          id[38] == L'\0' && CLSIDFromString(id, &guid) == S_OK;
    }
    if (success) target_ = L"Autofinance/Drive/" + std::wstring(id);
    RegCloseKey(key);
  }
  ReleaseMutex(mutex);
  CloseHandle(mutex);
  return success;
}

WindowsDriveChannel::WindowsDriveChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "autofinance/windows_drive",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* argument = call.arguments()
        ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (call.method_name() == "openBrowser") {
      const std::string prefix = "https://accounts.google.com/o/oauth2/v2/auth?";
      if (!argument || argument->size() > 16384 ||
          argument->compare(0, prefix.size(), prefix) != 0) {
        result->Error("unavailable");
        return;
      }
      const auto uri = Wide(*argument);
      const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr,
          L"open", uri.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      if (uri.empty() || opened <= 32) result->Error("unavailable");
      else result->Success();
      return;
    }
    if (call.method_name() != "read" && call.method_name() != "write" &&
        call.method_name() != "clear") {
      result->NotImplemented();
      return;
    }
    if (!EnsureTarget()) {
      result->Error("secureStorageFailure");
      return;
    }
    if (call.method_name() == "read") {
      PCREDENTIALW credential = nullptr;
      if (!CredReadW(target_.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
        if (GetLastError() == ERROR_NOT_FOUND) result->Success();
        else result->Error("secureStorageFailure");
        return;
      }
      if (credential->Persist != CRED_PERSIST_LOCAL_MACHINE ||
          credential->CredentialBlobSize == 0 ||
          credential->CredentialBlobSize > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
        FreeCredential(credential);
        result->Error("secureStorageFailure");
        return;
      }
      std::string payload(reinterpret_cast<char*>(credential->CredentialBlob),
          credential->CredentialBlobSize);
      FreeCredential(credential);
      result->Success(flutter::EncodableValue(payload));
      SecureZeroMemory(payload.data(), payload.size());
      return;
    }
    if (call.method_name() == "write") {
      if (!argument || argument->empty() ||
          argument->size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
        result->Error("secureStorageFailure");
        return;
      }
      CREDENTIALW credential = {};
      credential.Type = CRED_TYPE_GENERIC;
      credential.TargetName = target_.data();
      credential.CredentialBlobSize = static_cast<DWORD>(argument->size());
      credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(argument->data()));
      credential.Persist = CRED_PERSIST_LOCAL_MACHINE;  // Never enterprise/roaming.
      if (!CredWriteW(&credential, 0)) {
        result->Error("secureStorageFailure");
        return;
      }
      PCREDENTIALW checked = nullptr;
      const bool read = CredReadW(target_.c_str(), CRED_TYPE_GENERIC, 0, &checked) != FALSE;
      const bool equal = read && checked->Persist == CRED_PERSIST_LOCAL_MACHINE &&
          checked->CredentialBlobSize == argument->size() &&
          std::memcmp(checked->CredentialBlob, argument->data(), argument->size()) == 0;
      FreeCredential(checked);
      if (equal) result->Success();
      else result->Error("secureStorageFailure");
      return;
    }
    if (!CredDeleteW(target_.c_str(), CRED_TYPE_GENERIC, 0) &&
        GetLastError() != ERROR_NOT_FOUND) {
      result->Error("secureStorageFailure");
      return;
    }
    PCREDENTIALW residual = nullptr;
    if (CredReadW(target_.c_str(), CRED_TYPE_GENERIC, 0, &residual)) {
      FreeCredential(residual);
      result->Error("secureStorageFailure");
    } else if (GetLastError() != ERROR_NOT_FOUND) {
      result->Error("secureStorageFailure");
    } else {
      result->Success();
    }
  });
}
