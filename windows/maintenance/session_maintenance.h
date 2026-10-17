#pragma once

#include <array>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// In-process, current-user API for the installer host. Never serialize Secret.
namespace autofinance::maintenance {
enum class Status { ready, committed, cleared, closed, busy, blocked, conflict,
                    failed, cancelled };
enum class Action { install, update, repair, uninstall };
struct Error { Status status; };
struct Installation {
  std::wstring exe, key, support;
  std::array<unsigned, 4> version{};
};
struct Secret {
  std::vector<unsigned char> bytes;
  ~Secret();
  bool equals(const Secret& other) const;
};
enum class Phase { prepared, committed };
// Identifiers and phase ONLY. Written atomically and flushed before side effects.
struct Journal {
  std::wstring sourceKey, sourceId, destinationKey, destinationId;
  bool hadDestinationId = false;
  Phase phase = Phase::prepared;
};
struct Lease { virtual ~Lease() = default; };
class Store {
 public:
  virtual ~Store() = default;
  virtual Installation inspect(const std::wstring& exactExe) = 0;
  virtual Installation plan(const std::wstring& exactExe,
                           const std::wstring& stagedExe) = 0;
  virtual std::wstring newId() = 0;
  virtual std::unique_ptr<Lease> lock(const std::vector<Installation>& paths) = 0;
  virtual bool running(const Installation& path) = 0;
  virtual std::optional<std::wstring> id(const std::wstring& key) = 0;
  virtual void setId(const std::wstring& key, const std::wstring& id) = 0;
  virtual void removeId(const std::wstring& key) = 0;
  virtual std::unique_ptr<Secret> read(const std::wstring& id) = 0;
  virtual void write(const std::wstring& id, const Secret& secret) = 0;
  virtual void erase(const std::wstring& id) = 0;
  virtual std::optional<Journal> journal(const std::wstring& key) = 0;
  virtual void save(const Journal& journal) = 0;
  virtual void removeJournal(const std::wstring& key) = 0;
};
struct Inspection {
  Installation installation;
  std::optional<std::wstring> identity;
  bool hasSession = false, recoveryPending = false;
};
enum class Consent { transferLocalDriveSession };
struct Confirmation {
  Consent consent = Consent::transferLocalDriveSession;
  std::wstring operation, sourceExe, destinationExe;
};
// One host, one thread, one operation; destruction/abort always releases leases.
// Caller must retain this object through payload replacement and final checks.
class SessionMaintenance {
 public:
  explicit SessionMaintenance(Store& store) : store_(store) {}
  Status inspectInstallation(const std::wstring& exe, Inspection& out);
  Status prepareMaintenance(Action action, const std::wstring& destination,
      const std::array<unsigned, 4>& incomingVersion,
      const std::wstring& expectedSupport, const std::wstring& source = L"",
      const std::wstring& stagedExe = L"");
  Status requestClose();  // closed or busy: caller offers manual cooperative close.
  Status prepareAdoption(Confirmation& out);
  Status confirmAdoption(const Confirmation& confirmation);
  Status cleanupOwnSession();
  Status finishMaintenance();
  Status abortMaintenance();
 private:
  Store& store_;
  std::unique_ptr<Lease> lease_;
  Installation destination_, source_;
  Action action_ = Action::install;
  std::wstring operation_;
  std::wstring stagedExe_;
  bool sessionCleared_ = false;
  bool sessionCleanupStarted_ = false;
  bool adoptionCommitted_ = false;
  std::optional<Confirmation> confirmation_;
  void checkActive();
  void checkQuiet();
  void validateJournal(const Journal& journal);
  void rollback(const Journal& journal);
  void complete(const Journal& journal);
};
}  // namespace autofinance::maintenance
