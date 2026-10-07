#ifndef RUNNER_LOCAL_CSV_CHANNEL_H_
#define RUNNER_LOCAL_CSV_CHANNEL_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <atomic>
#include <memory>
#include <thread>

class LocalCsvChannel {
 public:
  LocalCsvChannel(flutter::BinaryMessenger* messenger, HWND owner);
  ~LocalCsvChannel();
  bool HandleMessage(UINT message);

 private:
  static constexpr UINT kReadComplete = WM_APP + 117;
  HWND owner_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  std::thread reader_;
  std::atomic<bool> stopping_{false};
  flutter::EncodableValue value_;
  std::string error_;
};

#endif
