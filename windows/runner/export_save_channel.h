#ifndef RUNNER_EXPORT_SAVE_CHANNEL_H_
#define RUNNER_EXPORT_SAVE_CHANNEL_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <atomic>
#include <memory>
#include <thread>

class ExportSaveChannel {
 public:
  ExportSaveChannel(flutter::BinaryMessenger* messenger, HWND owner);
  ~ExportSaveChannel();
  bool HandleMessage(UINT message);
 private:
  static constexpr UINT kSaveComplete = WM_APP + 118;
  HWND owner_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  std::thread writer_;
  std::atomic<bool> stopping_{false};
  std::string location_;
  std::string error_;
  bool incomplete_ = false;
};
#endif
