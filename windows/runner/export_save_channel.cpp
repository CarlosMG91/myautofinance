#include "export_save_channel.h"
#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>
#include <array>
#include <regex>
#include <string>

namespace {
std::wstring Wide(const std::string& text) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring value(size, L'\0');
  if (size) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), value.data(), size);
  return value;
}
std::string Utf8(const std::wstring& text) {
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string value(size, '\0');
  if (size) WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), value.data(), size, nullptr, nullptr);
  return value;
}
std::string Failure(DWORD error) {
  if (error == ERROR_ACCESS_DENIED || error == ERROR_PRIVILEGE_NOT_HELD)
    return "accessDenied";
  if (error == ERROR_DISK_FULL || error == ERROR_HANDLE_DISK_FULL)
    return "noSpace";
  if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS)
    return "conflict";
  if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ||
      error == ERROR_NOT_READY || error == ERROR_BAD_NETPATH ||
      error == ERROR_DEVICE_NOT_CONNECTED) return "unavailable";
  return "writeFailed";
}
}

ExportSaveChannel::ExportSaveChannel(flutter::BinaryMessenger* messenger, HWND owner)
    : owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "autofinance/export_save", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "save") { result->NotImplemented(); return; }
    if (pending_) { result->Error("busy", "Guardado en curso."); return; }
    const auto* args = call.arguments()
        ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    auto argument = [args](const char* key) -> std::string {
      if (!args) return {};
      const auto found = args->find(flutter::EncodableValue(key));
      if (found == args->end()) return {};
      const auto* value = std::get_if<std::string>(&found->second);
      return value ? *value : std::string();
    };
    const auto source = Wide(argument("sourcePath"));
    const auto name = argument("suggestedName");
    const auto attributes = GetFileAttributesW(source.c_str());
    if (source.empty() || source.find(L'\0') != std::wstring::npos ||
        attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY) ||
        !std::regex_match(name, std::regex("^autofinance-(datos|copia|prueba)(-[0-9TZ_-]+)?\\.zip$")) ||
        argument("mimeType") != "application/zip") {
      result->Error("invalidSource", "ZIP temporal no disponible."); return;
    }
    pending_ = std::move(result);
    Microsoft::WRL::ComPtr<IFileSaveDialog> dialog;
    HRESULT hr = CoCreateInstance(CLSID_FileSaveDialog, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
    DWORD options = 0;
    if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
    // Un nombre existente devuelve conflicto desde CREATE_NEW. No ofrecer una
    // confirmación de reemplazo que este puerto deliberadamente no realiza.
    if (SUCCEEDED(hr)) hr = dialog->SetOptions((options | FOS_FORCEFILESYSTEM |
        FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT) & ~FOS_OVERWRITEPROMPT);
    const COMDLG_FILTERSPEC filters[] = {{L"Archivo ZIP (*.zip)", L"*.zip"}};
    if (SUCCEEDED(hr)) hr = dialog->SetFileTypes(1, filters);
    if (SUCCEEDED(hr)) hr = dialog->SetDefaultExtension(L"zip");
    if (SUCCEEDED(hr)) hr = dialog->SetFileName(Wide(name).c_str());
    if (SUCCEEDED(hr)) hr = dialog->SetTitle(L"Guardar exportaci\u00f3n (nombre nuevo)");
    if (SUCCEEDED(hr)) hr = dialog->Show(owner_);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      pending_->Success(); pending_.reset(); return;
    }
    Microsoft::WRL::ComPtr<IShellItem> item;
    PWSTR path = nullptr;
    if (SUCCEEDED(hr)) hr = dialog->GetResult(item.GetAddressOf());
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(hr) || !path) {
      if (path) CoTaskMemFree(path);
      pending_->Error(hr == E_ACCESSDENIED ? "accessDenied" : "unavailable",
          "Destino no disponible."); pending_.reset(); return;
    }
    const std::wstring destination(path);
    CoTaskMemFree(path);
    error_.clear(); incomplete_ = false; location_ = Utf8(destination);
    writer_ = std::thread([this, source, destination]() {
      HANDLE from = CreateFileW(source.c_str(), GENERIC_READ, FILE_SHARE_READ,
          nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
      if (from == INVALID_HANDLE_VALUE) {
        error_ = "invalidSource";
      } else {
        // CREATE_NEW evita incluso carreras posteriores al diálogo. DELETE solo
        // permite eliminar mediante ESTE handle el incompleto que hemos creado.
        HANDLE to = CreateFileW(destination.c_str(), GENERIC_WRITE | DELETE, 0,
            nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (to == INVALID_HANDLE_VALUE) {
          error_ = Failure(GetLastError());
        } else {
          std::array<uint8_t, 65536> buffer;
          DWORD count = 0;
          while (!stopping_) {
            if (!ReadFile(from, buffer.data(), static_cast<DWORD>(buffer.size()), &count, nullptr)) {
              error_ = Failure(GetLastError()); break;
            }
            if (count == 0) break;
            DWORD offset = 0;
            while (offset < count) {
              DWORD written = 0;
              if (!WriteFile(to, buffer.data() + offset, count - offset, &written, nullptr)) {
                error_ = Failure(GetLastError()); break;
              }
              if (!written) { error_ = "writeFailed"; break; }
              offset += written;
            }
            if (!error_.empty()) break;
          }
          if (stopping_ && error_.empty()) error_ = "writeFailed";
          if (error_.empty() && !FlushFileBuffers(to)) error_ = Failure(GetLastError());
          if (!error_.empty()) {
            FILE_DISPOSITION_INFO disposition{TRUE};
            incomplete_ = !SetFileInformationByHandle(to, FileDispositionInfo,
                &disposition, sizeof(disposition));
          }
          if (!CloseHandle(to)) { error_ = "writeFailed"; incomplete_ = true; }
        }
        CloseHandle(from);
      }
      PostMessageW(owner_, kSaveComplete, 0, 0);
    });
  });
}

bool ExportSaveChannel::HandleMessage(UINT message) {
  if (message != kSaveComplete) return false;
  if (writer_.joinable()) writer_.join();
  if (pending_) {
    if (error_.empty()) pending_->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("status"), flutter::EncodableValue("saved")},
        {flutter::EncodableValue("location"), flutter::EncodableValue(location_)}}));
    else pending_->Error(error_, "No se pudo guardar el ZIP.", flutter::EncodableValue(
        flutter::EncodableMap{{flutter::EncodableValue("incompleteMayRemain"),
        flutter::EncodableValue(incomplete_)}}));
    pending_.reset();
  }
  return true;
}

ExportSaveChannel::~ExportSaveChannel() {
  channel_->SetMethodCallHandler(nullptr);
  stopping_ = true;
  if (writer_.joinable()) {
    CancelSynchronousIo(writer_.native_handle());
    writer_.join();
  }
}
