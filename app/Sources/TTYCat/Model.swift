// What the panel and the menu bar show, kept up to date once a second.
import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum Page: Equatable {
  case agents, pet, setup
  case extra(String)  // from an extension
}

@MainActor
final class TTYCatModel: ObservableObject {
  @Published var status: DaemonStatus?
  @Published var page = Page.agents
  @Published var petEvent: PetEvent?
  @Published var icon = MenuIcon.make(pose: .nap, tick: 0, faded: true, needs: 0)
  @Published var toast: String?
  @Published var hookInstalled: Bool?
  @Published var hookBusy = false
  @Published var loginState = SMAppService.mainApp.status
  @Published var problem: String?
  @Published var sampled = false
  @Published var selected: String?              // the agent whose page is open
  @Published var activity: [ActivityItem] = []
  @Published var answering: String?             // the rev of the prompt being answered
  @Published private(set) var pinnedAsk: String?
  @Published var notifyPermission = UNAuthorizationStatus.notDetermined
  @Published var notifyProblem: String?
  @Published var notifyAsks = UserDefaults.standard.object(forKey: "notifyAsks") as? Bool ?? true
  @Published var notifyFinishes = UserDefaults.standard.object(forKey: "notifyFinishes") as? Bool ?? true
  @Published var notifySound = UserDefaults.standard.object(forKey: "notifySound") as? Bool ?? true

  @Published var boardEverSeen = UserDefaults.standard.bool(forKey: "boardEverSeen")
  @Published var welcomed = UserDefaults.standard.bool(forKey: "welcomed")
  @Published var panelHeight: CGFloat = 0
  @Published var maxPanelHeight: CGFloat = 2000  // how far down the screen it can go
  @Published var firmwareImage = FirmwareImage.inApp()
  @Published var flashStarting = false
  @Published var firmwarePlan = FirmwarePlan.notConnected

  let supervisor = Supervisor()
  private var boardAsksSeen: Int?
  private var lastFlashState: String?
  private var seenNeeds: Set<String>?
  private var seenPetEv: Int?
  private var seenPetTotal: Int?
  private var seenPetLevel: Int?
  private var pendingHello: PetEvent.Kind?  // a welcome back, saved for when the Pet page is open to give it
  private var petTimer: Timer?
  var handsOffUntil = Date.distantPast
  var lastPanelClick = Date.distantPast
  private lazy var alerts = Alerts()  // lazily: it can't exist outside the app bundle, as in --preview
  private var planner = AlertPlanner()
  private var permissionTick = 0
  private var polling = false
  private var pollTimer: Timer?
  private var iconTimer: Timer?
  private var iconTick = 0
  private var iconKey = ""
  private var toastGeneration = 0

  var rows: [AgentRow] { status?.s ?? [] }
  var working: Int { rows.filter { $0.s == "working" }.count }
  var needs: Int { rows.filter(\.needsYou).count }
  var boardConnected: Bool { status?.board.connected == true }
  /// The board is optional. Someone without one shouldn't be told it's missing.
  var boardMatters: Bool { boardEverSeen || boardConnected || status?.board.silent?.isEmpty == false }
  var asks: [AgentRow] { rows.filter { $0.s == "blocked" } }
  var selectedRow: AgentRow? { rows.first { $0.id == selected } }

  /// The prompt on the card. It stays until it's settled: one arriving while you're reading
  /// or clicking waits its turn, instead of taking the place of the one you meant.
  var heroAsk: AgentRow? { asks.first { $0.rev == pinnedAsk } }

  /// Called with each new list.
  func pinAsk() {
    if asks.contains(where: { $0.rev == pinnedAsk }) { return }
    pinnedAsk = (asks.first { $0.ask != "terminal" } ?? asks.first)?.rev
  }
  var ownsDaemon: Bool { status.map { supervisor.ownsDaemon(pid: $0.pid) } ?? false }

  func finishWelcome() {
    welcomed = true
    UserDefaults.standard.set(true, forKey: "welcomed")
  }

  func start() {
    let supervisor = self.supervisor
    DispatchQueue.global(qos: .utility).async {
      _ = supervisor.hook("repair")  // the app may have moved since the hook was added
      DispatchQueue.main.async { MainActor.assumeIsolated { self.refreshHook() } }
    }
    alerts.start(model: self)
    for start in Extensions.started { start(self) }
    refreshPermission()  // never asks by itself: see turnOnNotifications
    poll()
    // Common modes: these must keep going while the panel's open.
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    let frames = Timer(timeInterval: 0.34, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.working > 0 else { return }
        self.iconTick += 1
        self.updateIcon()
      }
    }
    RunLoop.main.add(frames, forMode: .common)
    iconTimer = frames
  }

  private func poll() {
    if polling { return }
    polling = true
    let selected = self.selected
    DispatchQueue.global(qos: .utility).async {
      let data = Ctl.request(["t": "status"])
      let reply = data.flatMap { try? JSONDecoder().decode(DaemonStatus.self, from: $0) }
      let items = selected.flatMap { Self.fetchActivity($0) }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.polling = false
          self.status = reply
          Look.apply(reply?.look)
          for polled in Extensions.polled { polled(self) }
          self.pinAsk()
          self.stepAlerts()
          self.stepFirmware()
          self.stepPet()
          if let items, self.selected == selected { self.activity = items }
          // The agent ended: its page has nothing left to show.
          if let reply, let open = self.selected, !reply.s.contains(where: { $0.id == open }) {
            self.selected = nil
          }
          self.supervisor.tick(heard: reply != nil)
          self.problem = self.supervisor.problem
          self.updateIcon()
        }
      }
    }
  }

  nonisolated private static func fetchActivity(_ id: String) -> [ActivityItem]? {
    let data = Ctl.request(["t": "activity", "id": id])
    return data.flatMap { try? JSONDecoder().decode(ActivityReply.self, from: $0) }?.items
  }

  private func updateIcon() {
    let faded = status == nil || (boardEverSeen && !boardConnected)
    let dozing = status?.pet.map { PetLook.asleep(pet: $0, working: working, boardDim: status?.board.dim == true) } ?? false
    let pose: BitPose = faded ? .nap : needs > 0 ? .alert : working > 0 ? .work : dozing ? .nap : .idle
    let key = "\(pose)-\(faded)-\(needs)-\(pose == .work ? iconTick : 0)"
    if key == iconKey { return }
    iconKey = key
    icon = MenuIcon.make(pose: pose, tick: iconTick, faded: faded, needs: needs)
  }

  // ---------------------------------------------------------------- actions

  func select(_ row: AgentRow) {
    guard row.canOpen else { return }
    activity = []
    selected = row.id
    let id = row.id
    let done = row.s == "done"
    DispatchQueue.global(qos: .userInitiated).async {
      if done { _ = Ctl.request(["t": "app-act", "a": "seen", "id": id]) }  // as on the board
      let items = Self.fetchActivity(id)
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if self.selected == id, let items { self.activity = items }
        }
      }
    }
  }

  /// Goes only to the prompt with this rev: if it's gone, the daemon refuses and nothing is decided.
  func answer(_ row: AgentRow, action: String, picks: [[String: Any]]? = nil) {
    guard let rev = row.rev else { return }
    answer(id: row.id, rev: rev, action: action, picks: picks)
  }

  /// False if nothing was sent, because another answer is still on its way.
  @discardableResult
  func answer(id: String, rev: String, action: String, picks: [[String: Any]]? = nil) -> Bool {
    guard answering == nil else { return false }
    answering = rev
    var request: [String: Any] = ["t": "app-act", "a": action, "id": id, "rev": rev]
    if let picks { request["ans"] = picks }
    guard let body = try? JSONSerialization.data(withJSONObject: request) else {
      answering = nil
      return false
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let data = Ctl.send(body, timeout: 5)
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let ok = reply?["ok"] as? Bool ?? false
      let message = reply?["msg"] as? String
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.answering = nil
          if !ok { self.show(message?.isEmpty == false ? message! : "the daemon didn't answer") }
          self.poll()
        }
      }
    }
    return true
  }

  func open(_ row: AgentRow) {
    guard row.canOpen else { return }
    let id = row.id
    DispatchQueue.global(qos: .userInitiated).async {
      let data = Ctl.request(["t": "app-act", "a": "open", "id": id], timeout: 8)
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let ok = reply?["ok"] as? Bool ?? false
      let message = reply?["msg"] as? String
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if ok {
            StatusPanel.shared?.close()
          } else {
            self.show(message?.isEmpty == false ? message! : "couldn't open it")
          }
        }
      }
    }
  }

  func show(_ message: String) {
    toast = message
    if !Alerts.panelIsOpen { alerts.postNote(message) }  // nowhere else to see it
    toastGeneration += 1
    let generation = toastGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      MainActor.assumeIsolated {
        if generation == self.toastGeneration { self.toast = nil }
      }
    }
  }

  // ---------------------------------------------------------------- notifications

  /// Your eyes are probably on an agent whose pane is focused in a terminal in front, if you
  /// touched the Mac lately. Long enough without input, and it may need calling after all.
  private func watching() -> (AgentRow) -> Bool {
    let panel = Alerts.panelIsOpen
    let anyInput = CGEventType(rawValue: ~0)!
    let recent = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < 120
    let inFront = status?.term != nil && NSWorkspace.shared.frontmostApplication?.localizedName == status?.term
    return { row in panel || (recent && inFront && row.foc == true) }
  }

  private func stepAlerts() {
    permissionTick += 1
    if permissionTick % 5 == 0 { refreshPermission() }
    guard status != nil else { return }  // no news: everything stays as it is
    let allowed = notifyPermission == .authorized || notifyPermission == .provisional
    let steps = planner.plan(
      rows, now: Date(), watching: watching(), asks: allowed && notifyAsks, finishes: allowed && notifyFinishes)
    for step in steps {
      switch step {
      case .ask(let id):
        if let row = rows.first(where: { $0.id == id }) { alerts.postAsk(row, sound: notifySound) }
      case .finished(let id):
        if let row = rows.first(where: { $0.id == id }) { alerts.postFinished(row) }
      case .clear(let id):
        alerts.clear(id)
      }
    }
  }

  func alertReply(_ reply: AlertReply, id: String, rev: String, delivered: Date) {
    let row = rows.first { $0.id == id }
    switch reply {
    case .nothing:
      break
    case .show:
      page = .agents
      if let row { select(row) }
      Alerts.openPanel()
    case .open:
      guard let row else { return show("that agent has ended") }
      if row.s == "done" {  // seen, as when it's opened anywhere else
        DispatchQueue.global(qos: .userInitiated).async { _ = Ctl.request(["t": "app-act", "a": "seen", "id": id]) }
      }
      open(row)
    case .deny:
      sendAlertAnswer(id: id, rev: rev, action: "deny", picks: nil, delivered: delivered)
    case .choose(let number):
      sendAlertAnswer(id: id, rev: rev, action: "answer", picks: [["o": [number], "t": ""]], delivered: delivered)
    case .type(let text):
      sendAlertAnswer(id: id, rev: rev, action: "answer", picks: [["o": [Int](), "t": text]], delivered: delivered)
    }
  }

  /// As on the board: a click this soon after a prompt appears isn't an answer to it.
  private func sendAlertAnswer(id: String, rev: String, action: String, picks: [[String: Any]]?, delivered: Date) {
    let tooSoon = Date().timeIntervalSince(delivered) < 0.6
    if tooSoon || !answer(id: id, rev: rev, action: action, picks: picks) {
      planner.forget(id)  // the notification's been used up; the prompt still needs one
    }
  }

  func refreshPermission() {
    alerts.refreshPermission { status in
      DispatchQueue.main.async { MainActor.assumeIsolated { self.notifyPermission = status } }
    }
  }

  /// Only from a click. macOS answered a request made in the background with a refusal and no
  /// prompt, and remembered it; and starting up must not take the focus to ask from the front.
  func turnOnNotifications() {
    NSApp.activate()
    alerts.requestPermission { status, problem in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.notifyPermission = status
          self.notifyProblem = problem
        }
      }
    }
  }

  func setNotify(asks: Bool? = nil, finishes: Bool? = nil, sound: Bool? = nil) {
    if let asks {
      notifyAsks = asks
      UserDefaults.standard.set(asks, forKey: "notifyAsks")
    }
    if let finishes {
      notifyFinishes = finishes
      UserDefaults.standard.set(finishes, forKey: "notifyFinishes")
    }
    if let sound {
      notifySound = sound
      UserDefaults.standard.set(sound, forKey: "notifySound")
    }
  }

  func stopAlerts() { alerts.stop() }

  // ---------------------------------------------------------------- the pet

  /// Goes to the daemon: the board shows the change at its next update too.
  func petAct(_ action: String, arg: String = "", done: (() -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
      let data = Ctl.request(["t": "app-act", "a": action, "id": "", "rev": arg])
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let ok = reply?["ok"] as? Bool ?? false
      let message = reply?["msg"] as? String
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if ok {
            done?()
          } else {
            self.show(message?.isEmpty == false ? message! : "the daemon didn't answer")
          }
          self.poll()
        }
      }
    }
  }

  /// Agents come first, as on the board: something new leaves the pet at once. What was already
  /// waiting stays out of the way, with a line saying so.
  private func stepPet() {
    guard status != nil else { return }
    notePetEvents()
    let now = HandsOff.needs(in: rows)
    let fresh = seenNeeds.map { now.subtracting($0) } ?? []
    seenNeeds = now
    guard page == .pet, !fresh.isEmpty else { return }
    handsOffUntil = Date().addingTimeInterval(HandsOff.afterInterruption)
    page = .agents
  }

  /// A pat from either place, and turns agents finish, show the same here as on the board.
  private func notePetEvents() {
    guard let pet = status?.pet else { return }
    if let seen = seenPetEv, pet.ev != seen, let kind = PetEvent.Kind(rawValue: pet.evk ?? "") {
      if kind.isHello, page != .pet {
        pendingHello = kind
      } else {
        petEvent = PetEvent(kind: kind, at: Date())
      }
    }
    seenPetEv = pet.ev
    // A level can come from age alone, with no turn to show.
    if let total = seenPetTotal, let level = seenPetLevel, pet.total > total || pet.level > level {
      petEvent = PetEvent(kind: .reward, at: Date(), turns: max(0, pet.total - total), levelUp: pet.level > level)
    }
    seenPetTotal = pet.total
    seenPetLevel = pet.level
  }

  /// Quicker while you're looking at it, so a tap on the board shows here at once.
  func petPageOpen(_ open: Bool) {
    petTimer?.invalidate()
    petTimer = nil
    guard open, StatusPanel.shared != nil else { return }  // a --preview shows only its sample data
    if let kind = pendingHello {
      pendingHello = nil
      petEvent = PetEvent(kind: kind, at: Date())
    }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    petTimer = timer
  }

  /// What's waiting on you comes before the pet whenever the panel opens.
  func panelOpening() {
    DispatchQueue.global(qos: .userInitiated).async { _ = Ctl.request(["t": "app-act", "a": "pet-here", "id": ""]) }
    if page == .pet, needs > 0 {
      handsOffUntil = Date().addingTimeInterval(HandsOff.afterInterruption)
      page = .agents
    }
  }

  // ---------------------------------------------------------------- firmware

  var flashBusy: Bool { flashStarting || status?.flash?.busy == true }

  func stepFirmware() {
    let board = status?.board
    if board?.connected == true, !boardEverSeen {
      boardEverSeen = true
      UserDefaults.standard.set(true, forKey: "boardEverSeen")
    }
    firmwarePlan = FirmwarePlan.make(status: status, image: firmwareImage)
    noticeBoardAsking()

    // An update takes a while: you may have closed the panel by the time it ends.
    let state = status?.flash?.state
    if state != lastFlashState, let flash = status?.flash, lastFlashState != nil {
      if state == "done" { show("Board updated to \(flash.to ?? "the new firmware")") }
      if state == "failed" { show("Board update failed: \(flash.msg)") }
    }
    if state != nil { lastFlashState = state }
  }

  /// A board that can't approve yet was tapped: the prompt comes up here, where it can be answered.
  /// Said once, for that tap. Setup never nags about it: nothing should push anyone towards approving.
  private func noticeBoardAsking() {
    guard let board = status?.board else { return }
    let asks = board.asks ?? 0
    defer { boardAsksSeen = asks }
    guard let seen = boardAsksSeen, asks > seen else { return }
    page = .agents
    if let row = rows.first(where: { $0.id == board.asked && $0.s == "blocked" }) {
      pinnedAsk = row.rev
      select(row)
    }
    Alerts.openPanel()
    show("\(board.fw ?? "It") can't approve yet. Setup > Firmware can change that.")
  }

  /// `unknown`: you've agreed to overwrite a device that hasn't said what it is. `port`: which one.
  func updateFirmware(unknown: Bool = false, port: String? = nil) {
    guard !flashBusy, let folder = FirmwareImage.folder else { return }
    flashStarting = true
    DispatchQueue.global(qos: .userInitiated).async {
      // The image's hashes are checked first; that's quick.
      var request: [String: Any] = ["t": "flash", "dir": folder, "unknown": unknown]
      if let port { request["port"] = port }
      let data = Ctl.request(request, timeout: 8)
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let ok = reply?["ok"] as? Bool ?? false
      let message = reply?["msg"] as? String
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.flashStarting = false
          if !ok { self.show(message?.isEmpty == false ? message! : "the daemon didn't answer") }
          self.poll()
        }
      }
    }
  }

  /// Whether the custom firmware that's plugged in may say yes to prompts.
  func setDeviceApproves(_ name: String, _ on: Bool) {
    DispatchQueue.global(qos: .userInitiated).async {
      let data = Ctl.request(["t": "device", "fw": name, "approve": on], timeout: 3)
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      let ok = reply?["ok"] as? Bool ?? false
      let message = reply?["msg"] as? String
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if !ok { self.show(message?.isEmpty == false ? message! : "the daemon didn't answer") }
          self.poll()
        }
      }
    }
  }

  func restartDaemon() {
    supervisor.restart(runningPid: status?.pid)
    status = nil
    updateIcon()
  }

  func refreshHook() {
    let supervisor = self.supervisor
    DispatchQueue.global(qos: .utility).async {
      let result = supervisor.hook("status")
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self.hookInstalled = result.ok ? result.installed : nil }
      }
    }
  }

  func setHook(_ on: Bool) {
    hookBusy = true
    let supervisor = self.supervisor
    DispatchQueue.global(qos: .userInitiated).async {
      let changed = supervisor.hook(on ? "install" : "remove")
      let now = supervisor.hook("status")
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.hookBusy = false
          self.hookInstalled = now.ok ? now.installed : nil
          if !changed.ok { self.show("couldn't change ~/.claude/settings.json") }
        }
      }
    }
  }

  func refreshLogin() { loginState = SMAppService.mainApp.status }

  func setStartAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      show("login item: \(error.localizedDescription)")
    }
    refreshLogin()
  }
}
