#include "local_csv_channel.h"

#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>
#include <array>
#include <string>
#include <vector>

namespace {
std::string ReadError(DWORD error) {
  if (error == ERROR_ACCESS_DENIED || error == ERROR_PRIVILEGE_NOT_HELD)
    return "accessDenied";
  if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ||
      error == ERROR_NOT_READY || error == ERROR_BAD_NETPATH ||
      error == ERROR_DEVICE_NOT_CONNECTED) return "unavailable";
  return "readFailed";
}

std::string Utf8(const std::wstring& text) {
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (!size) return {};
  std::string value(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), value.data(), size, nullptr, nullptr);
  return value;
}
}  // namespace

LocalCsvChannel::LocalCsvChannel(flutter::BinaryMessenger* messenger, HWND owner)
    : owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "autofinance/local_csv",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "select") {
      result->NotImplemented();
      return;
    }
    if (pending_) {
      result->Error("busy", "Selección en curso.");
      return;
    }
    pending_ = std::move(result);
    // Diálogo modal del sistema: bombea mensajes. La lectura se hace fuera
    // del hilo de Flutter, y el resultado vuelve por la cola de la ventana.
    Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
    DWORD options = 0;
    if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) hr = dialog->SetOptions(
        (options | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM |
         FOS_NOCHANGEDIR | FOS_DONTADDTORECENT) & ~FOS_ALLOWMULTISELECT);
    const COMDLG_FILTERSPEC filters[] = {
        {L"CSV (*.csv)", L"*.csv"}, {L"Todos los archivos", L"*.*"}};
    if (SUCCEEDED(hr)) hr = dialog->SetFileTypes(2, filters);
    if (SUCCEEDED(hr)) hr = dialog->SetTitle(L"Seleccionar CSV");
    if (SUCCEEDED(hr)) hr = dialog->Show(owner_);
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      pending_->Success();
      pending_.reset();
      return;
    }
    Microsoft::WRL::ComPtr<IShellItem> item;
    PWSTR path = nullptr;
    if (SUCCEEDED(hr)) hr = dialog->GetResult(item.GetAddressOf());
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
    if (FAILED(hr) || !path) {
      if (path) CoTaskMemFree(path);
      pending_->Error(hr == E_ACCESSDENIED ? "accessDenied" : "unavailable",
          "Archivo no disponible.");
      pending_.reset();
      return;
    }
    const std::wstring selected(path);
    CoTaskMemFree(path);
    error_.clear();
    value_ = flutter::EncodableValue();
    reader_ = std::thread([this, selected]() {
      HANDLE file = CreateFileW(selected.c_str(), GENERIC_READ,
          FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file == INVALID_HANDLE_VALUE) {
        error_ = ReadError(GetLastError());
      } else {
        try {
          std::vector<uint8_t> bytes;
          std::array<uint8_t, 65536> buffer;
          DWORD count = 0;
          while (!stopping_) {
            if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                &count, nullptr)) {
              error_ = ReadError(GetLastError());
              break;
            }
            if (count == 0) break;
            bytes.insert(bytes.end(), buffer.begin(), buffer.begin() + count);
          }
          if (error_.empty() && !stopping_) {
            const auto name = Utf8(selected.substr(selected.find_last_of(L"\\/") + 1));
            value_ = flutter::EncodableValue(flutter::EncodableMap{
                {flutter::EncodableValue("name"), flutter::EncodableValue(name)},
                {flutter::EncodableValue("bytes"), flutter::EncodableValue(std::move(bytes))}});
          }
        } catch (...) {
          error_ = "readFailed";
        }
        CloseHandle(file);
      }
      PostMessageW(owner_, kReadComplete, 0, 0);
    });
  });
}

bool LocalCsvChannel::HandleMessage(UINT message) {
  if (message != kReadComplete) return false;
  if (reader_.joinable()) reader_.join();
  if (pending_) {
    if (error_.empty()) pending_->Success(value_);
    else pending_->Error(error_, "No se pudo leer el archivo seleccionado.");
    pending_.reset();
  }
  value_ = flutter::EncodableValue();
  return true;
}

LocalCsvChannel::~LocalCsvChannel() {
  channel_->SetMethodCallHandler(nullptr);
  stopping_ = true;
  if (reader_.joinable()) {
    CancelSynchronousIo(reader_.native_handle());
    reader_.join();
  }
}
