#pragma once

#include "session_maintenance.h"

namespace autofinance::maintenance {
struct NativePins;
// Windows-only, current token's HKCU/Credential Manager. No enumeration API.
class WindowsSessionStore final : public Store {
 public:
  Installation inspect(const std::wstring& exactExe) override;
  Installation plan(const std::wstring& exactExe,
                    const std::wstring& stagedExe) override;
  std::wstring newId() override;
  std::unique_ptr<Lease> lock(const std::vector<Installation>& paths) override;
  bool running(const Installation& path) override;
  std::optional<std::wstring> id(const std::wstring& key) override;
  void setId(const std::wstring& key, const std::wstring& id) override;
  void removeId(const std::wstring& key) override;
  std::unique_ptr<Secret> read(const std::wstring& id) override;
  void write(const std::wstring& id, const Secret& secret) override;
  void erase(const std::wstring& id) override;
  std::optional<Journal> journal(const std::wstring& key) override;
  void save(const Journal& journal) override;
  void removeJournal(const std::wstring& key) override;
 private:
  std::weak_ptr<NativePins> pins_;
};
std::wstring CurrentExecutable();
std::wstring SupportDirectory();
std::wstring DirectoryKey(const std::wstring& exactExe);
// Acquired BEFORE Flutter/plugins/SQLite. Held until process exit. Shared with
// other app instances, exclusive against maintenance, across logon sessions.
std::unique_ptr<Lease> AcquireApplicationLease();
}  // namespace autofinance::maintenance
