#include "session_maintenance.h"

namespace autofinance::maintenance {
namespace {
void Require(bool value, Status status = Status::conflict) {
  if (!value) throw Error{status};
}
template <class F> Status Result(F operation) {
  try { return operation(); }
  catch (const Error& error) { return error.status; }
  catch (...) { return Status::failed; }
}
}  // namespace
Secret::~Secret() {
  volatile unsigned char* p = bytes.data();
  for (size_t i = 0; i < bytes.size(); ++i) p[i] = 0;
}
bool Secret::equals(const Secret& other) const {
  if (bytes.size() != other.bytes.size()) return false;
  unsigned char difference = 0;
  for (size_t i = 0; i < bytes.size(); ++i) difference |= bytes[i] ^ other.bytes[i];
  return difference == 0;
}
Status SessionMaintenance::inspectInstallation(const std::wstring& exe,
                                               Inspection& out) {
  return Result([&] {
    Inspection value;
    value.installation = store_.inspect(exe);
    value.identity = store_.id(value.installation.key);
    if (value.identity) value.hasSession = !!store_.read(*value.identity);
    value.recoveryPending = !!store_.journal(value.installation.key);
    out = std::move(value);
    return Status::ready;
  });
}
void SessionMaintenance::checkActive() {
  Require(!!lease_ && !operation_.empty(), Status::blocked);
}
void SessionMaintenance::checkQuiet() {
  checkActive();
  Require(!store_.running(destination_) &&
      (source_.exe.empty() || !store_.running(source_)), Status::busy);
  // Metadata/path aliases may have changed since preparation.
  for (const auto* path : {&destination_, &source_}) {
    if (path->exe.empty()) continue;
    const auto checked = path == &destination_ && action_ == Action::install
        ? store_.plan(path->exe, stagedExe_) : store_.inspect(path->exe);
    Require(checked.key == path->key && checked.support == path->support,
            Status::blocked);
  }
}
Status SessionMaintenance::prepareMaintenance(Action action,
    const std::wstring& destination, const std::array<unsigned, 4>& incoming,
    const std::wstring& support, const std::wstring& source,
    const std::wstring& stagedExe) {
  return Result([&] {
    Require(!lease_, Status::blocked);
    Require(action == Action::install || action == Action::update ||
        action == Action::repair || action == Action::uninstall, Status::blocked);
    Require(incoming[3] > 0, Status::blocked);
    for (const auto part : incoming) Require(part <= 65535, Status::blocked);
    auto dest = action == Action::install ? store_.plan(destination, stagedExe)
                                         : store_.inspect(destination);
    Require(dest.support == support && !support.empty(), Status::blocked);
    if (!stagedExe.empty()) {
      const auto payload = store_.inspect(stagedExe);
      Require(payload.version == incoming && payload.support == support, Status::blocked);
    }
    // T05 uses its staged, validated EXE for initial installation. For existing
    // installs destination MUST be the actual installed EXE (not the staging EXE).
    Require(action == Action::uninstall || incoming >= dest.version, Status::blocked);
    Require(action != Action::repair || incoming == dest.version, Status::blocked);
    Require(action != Action::update || incoming > dest.version, Status::blocked);
    std::vector<Installation> paths{dest};
    Installation src;
    if (!source.empty()) {
      Require(action == Action::install, Status::blocked);
      src = store_.inspect(source);
      Require(src.key != dest.key && src.support == dest.support, Status::blocked);
      paths.push_back(src);
    }
    auto held = store_.lock(paths);
    Require(!!held, Status::busy);
    Require(!store_.running(dest) && (source.empty() || !store_.running(src)), Status::busy);
    const auto pending = store_.journal(dest.key);
    if (pending) Require(action == Action::install && !source.empty() &&
        pending->sourceKey == src.key && pending->destinationKey == dest.key);
    if (!source.empty()) {
      const auto reserved = store_.journal(src.key);
      Require(!reserved || (reserved->sourceKey == src.key &&
          reserved->destinationKey == dest.key));
    }
    destination_ = std::move(dest);
    source_ = std::move(src);
    action_ = action;
    stagedExe_ = stagedExe;
    operation_ = store_.newId();
    confirmation_.reset();
    sessionCleared_ = false;
    sessionCleanupStarted_ = false;
    adoptionCommitted_ = false;
    lease_ = std::move(held);
    return Status::ready;
  });
}
Status SessionMaintenance::requestClose() {
  return Result([&] { checkQuiet(); return Status::closed; });
}
void SessionMaintenance::validateJournal(const Journal& j) {
  Require(j.sourceKey == source_.key && j.destinationKey == destination_.key &&
      j.sourceId != j.destinationId && !j.sourceId.empty() && !j.destinationId.empty());
  const auto src = store_.id(j.sourceKey), dst = store_.id(j.destinationKey);
  Require(!src || *src == j.sourceId);
  Require(!dst || *dst == j.destinationId);
  Require(j.phase == Phase::committed || src == j.sourceId);
}
void SessionMaintenance::rollback(const Journal& j) {
  validateJournal(j);
  Require(j.phase == Phase::prepared);
  const auto source = store_.read(j.sourceId), destination = store_.read(j.destinationId);
  // After an interrupted legacy run either credential may have changed. An
  // identifier alone is insufficient authority to delete a different session.
  Require(!destination || (source && source->equals(*destination)));
  // Only our reserved GUID can be removed, never another destination identity.
  store_.erase(j.destinationId);
  Require(!store_.read(j.destinationId), Status::failed);
  if (!j.hadDestinationId) store_.removeId(j.destinationKey);
  store_.removeJournal(j.destinationKey);
}
void SessionMaintenance::complete(const Journal& j) {
  validateJournal(j);
  Require(j.phase == Phase::committed);
  Require(store_.id(j.destinationKey) == j.destinationId);
  const auto destination = store_.read(j.destinationId);
  Require(!!destination, Status::failed);
  // After commit the source may already have been deleted by a previous attempt.
  const auto source = store_.read(j.sourceId);
  Require(!source || source->equals(*destination));
  store_.erase(j.sourceId);
  Require(!store_.read(j.sourceId), Status::failed);
  store_.removeId(j.sourceKey);
  Require(!store_.id(j.sourceKey), Status::failed);
  // Keep the committed receipt until finishMaintenance: a lost response to
  // confirmAdoption must be recoverable without inferring success from a blob.
}
Status SessionMaintenance::prepareAdoption(Confirmation& out) {
  return Result([&] {
    checkQuiet();
    Require(action_ == Action::install && !source_.exe.empty(), Status::blocked);
    // Recovery never follows an unrelated journal/origin, even when destination
    // already has a credential. A committed journal is resumed only on confirm.
    const auto pending = store_.journal(destination_.key);
    if (pending) validateJournal(*pending);
    else {
      const auto sourceId = store_.id(source_.key);
      Require(sourceId && !!store_.read(*sourceId));
      const auto destinationId = store_.id(destination_.key);
      Require(!destinationId || !store_.read(*destinationId));
      Require(!store_.journal(source_.key));
    }
    confirmation_ = Confirmation{Consent::transferLocalDriveSession,
        operation_, source_.exe, destination_.exe};
    out = *confirmation_;
    return Status::ready;
  });
}
Status SessionMaintenance::confirmAdoption(const Confirmation& given) {
  return Result([&] {
    checkQuiet();
    Require(confirmation_ && given.consent == Consent::transferLocalDriveSession &&
        given.operation == operation_ && given.sourceExe == source_.exe &&
        given.destinationExe == destination_.exe, Status::blocked);
    auto pending = store_.journal(destination_.key);
    if (pending) {
      validateJournal(*pending);
      if (pending->phase == Phase::committed) {
        complete(*pending);
        adoptionCommitted_ = true;
        confirmation_.reset();
        return Status::committed;
      }
      rollback(*pending);
    }
    const auto src = store_.id(source_.key), dst = store_.id(destination_.key);
    Require(src && (!dst || !store_.read(*dst)));
    auto secret = store_.read(*src);
    Require(!!secret);
    Journal j{source_.key, *src, destination_.key,
        dst ? *dst : store_.newId(), !!dst, Phase::prepared};
    Require(j.sourceId != j.destinationId);
    // The random reservation itself must be vacant, including orphan credentials.
    Require(!store_.read(j.destinationId));
    store_.save(j);
    try {
      store_.write(j.destinationId, *secret);
      auto checked = store_.read(j.destinationId);
      Require(checked && checked->equals(*secret), Status::failed);
      store_.setId(j.destinationKey, j.destinationId);
      Require(store_.id(j.destinationKey) == j.destinationId, Status::failed);
      j.phase = Phase::committed;
      store_.save(j);  // durable commit BEFORE deleting source
    } catch (...) {
      // A failed flush can still have persisted the commit. Re-read, never guess.
      const auto durable = store_.journal(destination_.key);
      if (durable && durable->phase == Phase::prepared) rollback(*durable);
      throw;
    }
    complete(j);
    adoptionCommitted_ = true;
    confirmation_.reset();
    return Status::committed;
  });
}
Status SessionMaintenance::cleanupOwnSession() {
  return Result([&] {
    checkQuiet();
    Require(action_ == Action::uninstall && source_.exe.empty(), Status::blocked);
    Require(!store_.journal(destination_.key), Status::blocked);
    const auto id = store_.id(destination_.key);
    sessionCleanupStarted_ = true;
    if (id) {
      store_.erase(*id);
      Require(!store_.read(*id), Status::failed);
    }
    store_.removeId(destination_.key);
    Require(!store_.id(destination_.key), Status::failed);
    sessionCleared_ = true;
    return Status::cleared;
  });
}
Status SessionMaintenance::finishMaintenance() {
  const auto result = Result([&] {
    checkActive();
    Require(action_ != Action::uninstall || sessionCleared_, Status::blocked);
    Require(!store_.running(destination_) &&
        (source_.exe.empty() || !store_.running(source_)), Status::busy);
    const auto pending = store_.journal(destination_.key);
    if (pending) {
      Require(adoptionCommitted_ && pending->phase == Phase::committed, Status::blocked);
      complete(*pending);
      store_.removeJournal(destination_.key);
    }
    return Status::ready;
  });
  lease_.reset(); operation_.clear(); confirmation_.reset();
  return result;
}
Status SessionMaintenance::abortMaintenance() {
  const auto result = Result([&] {
    checkActive();
    const auto j = store_.journal(destination_.key);
    if (j) {
      Require(j->phase == Phase::prepared, Status::blocked);
      rollback(*j);
    }
    if (action_ == Action::uninstall && sessionCleanupStarted_)
      return sessionCleared_ ? Status::cleared : Status::blocked;
    return Status::cancelled;
  });
  lease_.reset(); operation_.clear(); confirmation_.reset();
  return result;
}
}  // namespace autofinance::maintenance
