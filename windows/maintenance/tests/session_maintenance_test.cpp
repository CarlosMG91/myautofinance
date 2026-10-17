#include "windows_session_store.h"

#include <functional>
#include <iostream>
#include <map>
#include <stdexcept>

using namespace autofinance::maintenance;
#define CHECK(x) do { if (!(x)) throw std::runtime_error(#x); } while (false)
namespace {
const std::wstring src = L"C:\\origen á\\myautofinance.exe";
const std::wstring dst = L"C:\\Programs\\Autofinance\\myautofinance.exe";
const std::wstring support = L"R:\\Perfil redirigido\\com.carlosmg91\\Autofinance";
const std::array<unsigned, 4> version{0, 1, 0, 1};
struct State {
  std::map<std::wstring, std::wstring> ids;
  std::map<std::wstring, std::vector<unsigned char>> secrets;
  std::map<std::wstring, Journal> journals;
};
struct MemoryStore : Store {
  State state;
  std::vector<State> snapshots;
  bool held = false, appRunning = false, denyLock = false, corruptRead = false;
  int serial = 0, mutations = 0, failAt = 0;
  Installation inspect(const std::wstring& exe) override {
    if (exe != src && exe != dst) throw Error{Status::blocked};
    return {exe, exe == src ? L"source" : L"destination", support, version};
  }
  Installation plan(const std::wstring& exe, const std::wstring&) override { return inspect(exe); }
  std::wstring newId() override { return L"reserved-" + std::to_wstring(++serial); }
  struct Hold : Lease {
    bool& held;
    explicit Hold(bool& value) : held(value) { held = true; }
    ~Hold() override { held = false; }
  };
  std::unique_ptr<Lease> lock(const std::vector<Installation>&) override {
    if (held || denyLock) throw Error{Status::busy};
    return std::make_unique<Hold>(held);
  }
  bool running(const Installation&) override { return appRunning; }
  std::optional<std::wstring> id(const std::wstring& key) override {
    auto found = state.ids.find(key);
    return found == state.ids.end() ? std::optional<std::wstring>{} : found->second;
  }
  void mutation() {
    snapshots.push_back(state);
    if (++mutations == failAt) throw Error{Status::failed};
  }
  void setId(const std::wstring& key, const std::wstring& id) override {
    state.ids[key] = id; mutation();
  }
  void removeId(const std::wstring& key) override { state.ids.erase(key); mutation(); }
  std::unique_ptr<Secret> read(const std::wstring& id) override {
    const auto found = state.secrets.find(id);
    if (found == state.secrets.end()) return {};
    auto value = std::make_unique<Secret>(); value->bytes = found->second;
    if (corruptRead && id.find(L"reserved-") == 0) value->bytes = {99};
    return value;
  }
  void write(const std::wstring& id, const Secret& secret) override {
    state.secrets[id] = secret.bytes; mutation();
  }
  void erase(const std::wstring& id) override { state.secrets.erase(id); mutation(); }
  std::optional<Journal> journal(const std::wstring& key) override {
    for (const auto& entry : state.journals)
      if (entry.first == key || entry.second.sourceKey == key) return entry.second;
    return {};
  }
  void save(const Journal& j) override { state.journals[j.destinationKey] = j; mutation(); }
  void removeJournal(const std::wstring& key) override { state.journals.erase(key); mutation(); }
  void seed() {
    state.ids[L"source"] = L"original";
    state.secrets[L"original"] = {1, 2, 3, 4};
    state.ids[L"unrelated"] = L"other";
    state.secrets[L"other"] = {7, 8};
  }
};
void Begin(SessionMaintenance& service, bool adoption = true, Action action = Action::install) {
  CHECK(service.prepareMaintenance(action, dst, version, support, adoption ? src : L"") == Status::ready);
}
Confirmation Prepare(SessionMaintenance& service) {
  Confirmation confirmation;
  CHECK(service.prepareAdoption(confirmation) == Status::ready);
  return confirmation;
}
void Preserved(const MemoryStore& store) {
  CHECK(store.state.ids.at(L"unrelated") == L"other");
  CHECK(store.state.secrets.at(L"other") == std::vector<unsigned char>({7, 8}));
}
void Transferred(MemoryStore& store) {
  CHECK(!store.id(L"source"));
  CHECK(!store.read(L"original"));
  CHECK(store.id(L"destination") && *store.id(L"destination") != L"original");
  CHECK(store.read(*store.id(L"destination"))->bytes == std::vector<unsigned char>({1, 2, 3, 4}));
  CHECK(!store.journal(L"destination"));
  Preserved(store);
}
}  // namespace
int main() {
  int cases = 0;
  auto test = [&](const char* name, auto body) {
    try { body(); ++cases; }
    catch (const std::exception& e) { std::cerr << name << ": " << e.what() << '\n'; throw; }
  };
  test("native directory hash retains case and folder semantics", [] {
    CHECK(DirectoryKey(L"C:\\Programs\\Autofinance\\myautofinance.exe") ==
        DirectoryKey(L"c:\\programs\\AUTOFINANCE\\copied.exe"));
    CHECK(DirectoryKey(L"C:\\Programs\\Autofinance\\myautofinance.exe") !=
        DirectoryKey(L"C:\\Programs\\Other\\myautofinance.exe"));
    CHECK(DirectoryKey(L"C:\\Programs\\Autofinance\\myautofinance.exe").size() == 64);
  });
  test("inspection is read only", [] {
    MemoryStore store; SessionMaintenance service(store); Inspection out;
    CHECK(service.inspectInstallation(dst, out) == Status::ready);
    CHECK(out.installation.support == support && !out.identity && !out.hasSession);
    CHECK(store.mutations == 0 && store.serial == 0);
    CHECK(service.inspectInstallation(L"ambiguous;paths", out) == Status::blocked);
  });
  test("metadata support mismatch", [] {
    MemoryStore store; SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::install, dst, version, L"other") == Status::blocked);
    CHECK(store.mutations == 0);
  });
  test("numeric downgrade and version action", [] {
    MemoryStore store; SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::update, dst, {0,0,99,99}, support) == Status::blocked);
    CHECK(service.prepareMaintenance(Action::update, dst, version, support) == Status::blocked);
    CHECK(service.prepareMaintenance(Action::repair, dst, {0,1,0,2}, support) == Status::blocked);
    CHECK(store.mutations == 0);
  });
  test("busy and lease exclusion", [] {
    MemoryStore store; SessionMaintenance service(store); store.appRunning = true;
    CHECK(service.prepareMaintenance(Action::install, dst, version, support) == Status::busy);
    CHECK(!store.held); store.appRunning = false; Begin(service, false);
    SessionMaintenance second(store);
    CHECK(second.prepareMaintenance(Action::install, dst, version, support) == Status::busy);
    store.appRunning = true; CHECK(service.requestClose() == Status::busy);
    CHECK(service.abortMaintenance() == Status::cancelled && !store.held);
  });
  test("exact distinct origin", [] {
    MemoryStore store; store.seed(); SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::install, dst, version, support, dst) == Status::blocked);
    CHECK(service.prepareMaintenance(Action::install, dst, version, support, L"candidates") == Status::blocked);
    CHECK(store.mutations == 0);
  });
  test("copying EXE has no session", [] {
    MemoryStore store; store.seed(); SessionMaintenance service(store); Inspection out;
    CHECK(service.inspectInstallation(dst, out) == Status::ready && !out.hasSession);
    Begin(service, false); CHECK(service.finishMaintenance() == Status::ready);
    CHECK(store.id(L"source") == L"original" && !store.id(L"destination"));
  });
  test("typed confirmation required and bound", [] {
    MemoryStore store; store.seed(); SessionMaintenance service(store); Begin(service);
    CHECK(service.confirmAdoption({}) == Status::blocked);
    auto consent = Prepare(service), wrong = consent; wrong.sourceExe = dst;
    CHECK(service.confirmAdoption(wrong) == Status::blocked);
    wrong = consent; wrong.operation = L"stale";
    CHECK(service.confirmAdoption(wrong) == Status::blocked);
    CHECK(store.mutations == 0);
    CHECK(service.confirmAdoption(consent) == Status::committed);
    CHECK(service.finishMaintenance() == Status::ready); Transferred(store);
    CHECK(service.confirmAdoption(consent) == Status::blocked);
  });
  test("occupied destination cannot be overwritten", [] {
    MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"other";
    SessionMaintenance service(store); Begin(service); Confirmation out;
    CHECK(service.prepareAdoption(out) == Status::conflict);
    CHECK(store.mutations == 0); Preserved(store);
  });
  test("revalidation after confirmation", [] {
    MemoryStore store; store.seed(); SessionMaintenance service(store); Begin(service);
    auto consent = Prepare(service); store.state.ids[L"destination"] = L"other";
    CHECK(service.confirmAdoption(consent) == Status::conflict); Preserved(store);
  });
  test("cancel before commit changes nothing", [] {
    MemoryStore store; store.seed(); SessionMaintenance service(store); Begin(service);
    Prepare(service); CHECK(service.abortMaintenance() == Status::cancelled);
    CHECK(store.mutations == 0 && store.id(L"source") == L"original");
  });
  test("empty existing destination identity retained", [] {
    MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"empty";
    SessionMaintenance service(store); Begin(service);
    CHECK(service.confirmAdoption(Prepare(service)) == Status::committed);
    CHECK(service.finishMaintenance() == Status::ready);
    CHECK(store.id(L"destination") == L"empty"); Transferred(store);
  });
  test("verification failure preserves source and fails closed", [] {
    MemoryStore store; store.seed(); store.corruptRead = true;
    SessionMaintenance service(store); Begin(service);
    CHECK(service.confirmAdoption(Prepare(service)) == Status::conflict);
    CHECK(store.id(L"source") == L"original" && store.read(L"original"));
    CHECK(!store.id(L"destination") && store.journal(L"destination"));
    store.corruptRead = false;
    CHECK(service.abortMaintenance() == Status::cancelled);
    CHECK(!store.journal(L"destination")); Preserved(store);
  });
  test("update repair never cleanup", [] {
    for (const auto action : {Action::update, Action::repair}) {
      MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"other";
      SessionMaintenance service(store);
      CHECK(service.prepareMaintenance(action, dst,
          action == Action::update ? std::array<unsigned,4>{0,1,0,2} : version, support) == Status::ready);
      CHECK(service.cleanupOwnSession() == Status::blocked);
      CHECK(service.requestClose() == Status::closed && service.finishMaintenance() == Status::ready);
      CHECK(store.mutations == 0); Preserved(store);
    }
  });
  test("uninstall own only and idempotent", [] {
    MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"mine";
    store.state.secrets[L"mine"] = {5};
    SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    CHECK(service.cleanupOwnSession() == Status::cleared);
    CHECK(service.cleanupOwnSession() == Status::cleared);
    CHECK(!store.read(L"mine") && !store.id(L"destination"));
    CHECK(service.finishMaintenance() == Status::ready);
    CHECK(store.id(L"source") == L"original"); Preserved(store);
  });
  test("uninstall must complete cleanup", [] {
    MemoryStore store; SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    CHECK(service.finishMaintenance() == Status::blocked && !store.held);
  });
  test("failed uninstall retains retry identity", [] {
    MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"mine";
    store.state.secrets[L"mine"] = {5}; store.failAt = 1;
    SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    CHECK(service.cleanupOwnSession() == Status::failed);
    CHECK(store.id(L"destination") == L"mine");
    CHECK(service.cleanupOwnSession() == Status::cleared); Preserved(store);
  });
  test("crash at every durable boundary resumes safely", [] {
    MemoryStore original; original.seed();
    { SessionMaintenance service(original); Begin(service);
      CHECK(service.confirmAdoption(Prepare(service)) == Status::committed);
      CHECK(service.finishMaintenance() == Status::ready); }
    CHECK(original.snapshots.size() >= 7);
    for (const auto& snapshot : original.snapshots) {
      MemoryStore store; store.state = snapshot; store.serial = 100;
      SessionMaintenance service(store); Begin(service);
      if (store.journal(L"destination")) {
        CHECK(service.confirmAdoption(Prepare(service)) == Status::committed);
      }
      CHECK(service.finishMaintenance() == Status::ready);
      Transferred(store);
    }
  });
  test("I/O failure at every mutation preserves a recoverable session", [] {
    for (int fault = 1; fault <= 10; ++fault) {
      MemoryStore store; store.seed(); store.failAt = fault;
      { SessionMaintenance service(store); Begin(service);
        if (service.confirmAdoption(Prepare(service)) == Status::committed)
          service.finishMaintenance(); }
      CHECK(store.read(L"original") ||
          (store.id(L"destination") && store.read(*store.id(L"destination"))));
      store.failAt = 0;
      SessionMaintenance retry(store); Begin(retry);
      if (store.journal(L"destination") || !store.id(L"destination"))
        CHECK(retry.confirmAdoption(Prepare(retry)) == Status::committed);
      CHECK(retry.finishMaintenance() == Status::ready);
      Transferred(store);
    }
  });
  test("unrelated recovery journal fails closed", [] {
    MemoryStore store; store.seed();
    store.state.journals[L"destination"] = {L"other-origin", L"unknown", L"destination", L"new"};
    SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::install, dst, version, support, src) == Status::conflict);
    CHECK(store.mutations == 0 && !store.held);
  });
  test("destructor releases exclusion", [] {
    MemoryStore store; { SessionMaintenance service(store); Begin(service, false); CHECK(store.held); }
    CHECK(!store.held);
  });
  test("pending transfer blocks update and uninstall", [] {
    MemoryStore store; store.seed();
    store.state.journals[L"destination"] = {L"source", L"original", L"destination", L"new"};
    SessionMaintenance service(store);
    CHECK(service.prepareMaintenance(Action::repair, dst, version, support) == Status::conflict);
    CHECK(service.prepareMaintenance(Action::uninstall, dst, version, support) == Status::conflict);
    CHECK(!store.held && store.mutations == 0);
  });
  test("committed recovery preserves conflicting destination", [] {
    MemoryStore store; store.seed();
    store.state.ids[L"destination"] = L"reserved-99";
    store.state.secrets[L"reserved-99"] = {99};
    store.state.journals[L"destination"] = {L"source", L"original", L"destination", L"reserved-99", false, Phase::committed};
    SessionMaintenance service(store); Begin(service);
    CHECK(service.confirmAdoption(Prepare(service)) == Status::conflict);
    CHECK(store.read(L"original") && store.read(L"reserved-99"));
    CHECK(service.abortMaintenance() == Status::blocked && !store.held);
  });
  test("precommit rollback preserves existing empty identity", [] {
    MemoryStore store; store.seed(); store.state.ids[L"destination"] = L"empty";
    store.state.journals[L"destination"] = {L"source", L"original", L"destination", L"empty", true, Phase::prepared};
    store.state.secrets[L"empty"] = {1, 2, 3, 4};
    SessionMaintenance service(store); Begin(service);
    CHECK(service.abortMaintenance() == Status::cancelled);
    CHECK(store.id(L"destination") == L"empty" && !store.read(L"empty"));
    CHECK(store.read(L"original") && !store.journal(L"destination"));
  });
  test("uninstall absent identity does not create one", [] {
    MemoryStore store; SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    const auto serial = store.serial;
    CHECK(service.cleanupOwnSession() == Status::cleared && store.state.ids.empty());
    CHECK(store.serial == serial && store.state.secrets.empty());
  });
  test("precommit recovery cannot erase a newly changed credential", [] {
    MemoryStore store; store.seed();
    store.state.journals[L"destination"] = {L"source", L"original", L"destination", L"new", false, Phase::prepared};
    store.state.secrets[L"new"] = {99};
    SessionMaintenance service(store); Begin(service);
    CHECK(service.confirmAdoption(Prepare(service)) == Status::conflict);
    CHECK(store.read(L"new") && store.read(L"original"));
    CHECK(service.abortMaintenance() == Status::conflict && !store.held);
  });
  test("cancel after uninstall cleanup reports disconnection", [] {
    MemoryStore store; SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    CHECK(service.cleanupOwnSession() == Status::cleared);
    CHECK(service.abortMaintenance() == Status::cleared && !store.held);
  });
  test("cancel after partial cleanup reports pending cleanup", [] {
    MemoryStore store; store.state.ids[L"destination"] = L"mine";
    store.state.secrets[L"mine"] = {5}; store.failAt = 1;
    SessionMaintenance service(store); Begin(service, false, Action::uninstall);
    CHECK(service.cleanupOwnSession() == Status::failed);
    CHECK(service.abortMaintenance() == Status::blocked && !store.held);
    CHECK(store.id(L"destination") == L"mine");
  });
  std::cout << cases << " maintenance cases passed (memory store, no credentials accessed)\n";
}
