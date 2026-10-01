#ifndef RUNNER_WINDOWS_DRIVE_CHANNEL_H_
#define RUNNER_WINDOWS_DRIVE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <string>

// Credential Manager local; no credentials are written to application files.
class WindowsDriveChannel {
 public:
  explicit WindowsDriveChannel(flutter::BinaryMessenger* messenger);
 private:
  bool EnsureTarget();
  std::wstring target_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
