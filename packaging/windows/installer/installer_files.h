#pragma once
#include <windows.h>
#include <array>
#include <filesystem>
#include <string>
#include <vector>

namespace autofinance::installer {
using Version = std::array<unsigned, 4>;
inline constexpr wchar_t kAppId[] = L"{82D31B27-9717-4DB7-AB32-D098BF3C2859}";
inline constexpr wchar_t kManifest[] = L".autofinance-files";
inline constexpr wchar_t kPending[] = L".autofinance-pending";
inline constexpr wchar_t kPrevious[] = L".autofinance-previous";
struct File { std::wstring path, hash; unsigned long long size = 0; };
struct Manifest { Version version{}; std::vector<File> files; };
Version ParseVersion(const std::wstring& text, wchar_t separator = L'.');
std::wstring VersionText(const Version& version);
Manifest ReadManifest(const std::filesystem::path& path);
std::wstring HashFile(const std::filesystem::path& path);
void ValidateRoot(const std::filesystem::path& root);
// Only package-relative paths; rejects data/credentials, links and aliases.
void ValidateFile(const std::filesystem::path& root, const std::wstring& relative);
void VerifyManifest(const std::filesystem::path& root, const Manifest& manifest);
void WriteReceipt(const std::filesystem::path& root, const Manifest& manifest);
void PruneOwnedDirectories(const std::filesystem::path& root, const Manifest& manifest);

// Binarios only. Holds denial-of-read/write handles until completion. The T03
// destination EXE pin is retained by the caller and shares DELETE for rename.
class Replacement {
 public:
  Replacement(std::filesystem::path root, Manifest incoming);
  ~Replacement();
  void prepare();
  void verify();
  void seal() { complete_ = true; }
  void complete(bool keepReceipt = false);
  void acknowledge();
  bool rollback();
  bool recovery() const { return recovering_; }
 private:
  std::filesystem::path root_;
  Manifest incoming_, previous_, pending_;
  std::vector<std::wstring> owned_, moved_;
  std::vector<HANDLE> pins_;
  bool recovering_ = false, started_ = false, verified_ = false, complete_ = false;
  void release();
  void removeBackupFiles();
};
}  // namespace autofinance::installer
