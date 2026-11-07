// A menu bar app with no Dock icon. A few flags exist for the build and for testing.
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model: TTYCatModel
  private var panel: StatusPanel?
  private var termSource: DispatchSourceSignal?

  init(model: TTYCatModel) { self.model = model }

  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated { panel = StatusPanel(model: model) }
    // `kill` and logout should stop the daemon too, not leave it behind.
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    termSource = source
    MainActor.assumeIsolated {
      if AppMover.offerAtLaunch() { return }  // it opens again from Applications
      // The first time, a menu bar app is only an icon: open the panel, so the welcome is seen.
      if !model.welcomed {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          MainActor.assumeIsolated { self?.panel?.open() }
        }
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      model.stopAlerts()  // their buttons would find nothing to answer
      model.supervisor.stopForQuit()
    }
  }
}

@main
enum Entry {
  static func main() {
    Pixel.registerFonts()
    MainActor.assumeIsolated { Extensions.install() }
    let args = CommandLine.arguments
    if args.count >= 3, args[1] == "--iconset" {
      do {
        try MenuIcon.writeIconset(to: args[2])
      } catch {
        print("iconset: \(error)")
        exit(1)
      }
      exit(0)
    }
    if args.count >= 3, args[1] == "--preview" {
      MainActor.assumeIsolated { Preview.write(to: args[2], scene: args.count > 3 ? args[3] : "busy") }
      exit(0)
    }
    MainActor.assumeIsolated {
      let app = NSApplication.shared
      let model = TTYCatModel()
      let delegate = AppDelegate(model: model)
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      model.start()  // before launch finishes: a click on a notification can be what starts the app
      withExtendedLifetime(delegate) { app.run() }
    }
  }
}

// Renders the panel with sample data, so its look can be checked without opening the menu.
@MainActor
enum Preview {
  static func write(to path: String, scene: String) {
    let model = TTYCatModel()
    model.hookInstalled = scene == "welcome" ? false : true
    model.welcomed = scene != "welcome"
    model.boardEverSeen = scene != "welcome" && scene != "noboard"
    model.loginState = scene == "welcome" ? .notRegistered : .enabled
    model.notifyPermission = scene == "setup-denied" ? .denied : scene == "setup-new" || scene == "welcome" ? .notDetermined : .authorized
    let working = { (i: Int, project: String, detail: String) in
      AgentRow(id: "w\(i)", s: "working", a: "CC", n: "Claude", p: project, d: detail, age: Double(30 + i * 40))
    }
    var rows = [
      working(1, "web-shop", "Edit: Cart.tsx"),
      AgentRow(id: "s1", s: "working", a: "PI", n: "Pi", p: "riff-9", d: "write: sequencer.c", host: "studio", age: 130),
      AgentRow(id: "i1", s: "idle", a: "CC", n: "Claude", p: "docs", d: "waiting for prompt", age: 840),
    ]
    let command = AgentRow(
      id: "b1", s: "blocked", a: "CC", n: "Claude", p: "checkout-api", d: "npm run test:integration", tool: "BASH", age: 12,
      verb: "wants to run", body: "npm run test:integration -- --grep payment && docker compose down", rev: "r1", ask: "approve")
    switch scene {
    case "needs":
      rows.insert(command, at: 0)
      rows.insert(AgentRow(id: "e1", s: "error", a: "CX", n: "Codex", p: "api-gateway", d: "pnpm build: exit 1", age: 180), at: 1)
    case "diff":
      rows.insert(
        AgentRow(
          id: "b2", s: "blocked", a: "OC", n: "Claude", p: "infra", d: "gateway.tf +2 -1", tool: "EDIT", age: 40,
          verb: "wants to change", body: "- timeout = 30\n+ timeout = 90\n+ retry { max = 3 }", rev: "r2", ask: "approve",
          file: "gateway.tf", add: 2, del: 1),
        at: 0)
    case "long":
      rows.insert(
        AgentRow(
          id: "b3", s: "blocked", a: "CC", n: "Claude", p: "checkout-api", d: "rm -rf build", tool: "BASH", age: 3,
          verb: "wants to run", body: (1...30).map { "step \($0): rm -rf build dist .cache && npm ci" }.joined(separator: "\n"), rev: "r3", ask: "approve"),
        at: 0)
    case "question", "questions":
      var qs = [
        Question(q: "Which database should the new service use?", m: false, o: [
          QuestionOption(l: "Postgres", d: "What the other services run on"),
          QuestionOption(l: "SQLite", d: "Simple, one file, no server"),
          QuestionOption(l: "DynamoDB", d: "Managed, but new to the team"),
        ])
      ]
      if scene == "questions" {
        qs.append(Question(q: "Which areas should the audit cover?", m: true, o: [
          QuestionOption(l: "Auth", d: "Login and sessions"), QuestionOption(l: "Payments", d: ""),
        ]))
      }
      rows.insert(
        AgentRow(
          id: "q1", s: "blocked", a: "CC", n: "Claude", p: "checkout-api", d: qs[0].q, tool: "ASK", age: 4, verb: "is asking",
          rev: "r4", ask: "choice", qs: qs),
        at: 0)
    case "terminal":
      rows.insert(
        AgentRow(
          id: "t1", s: "blocked", a: "CX", n: "Codex", p: "design-tokens", d: "pnpm add -D culori@4", tool: "SHELL", age: 60,
          verb: "wants to run", body: "pnpm add -D culori@4 --filter tokens", rev: "r5", ask: "terminal",
          note: "Codex can only be answered in its terminal"),
        at: 0)
    case "detail":
      model.selected = "w1"
      model.activity = [
        ActivityItem(age: "-4s", tone: 0, text: "Edit src/cart/Cart.tsx"),
        ActivityItem(age: "-9s", tone: 1, text: "Failed: $ npm run test -- cart"),
        ActivityItem(age: "-31s", tone: 2, text: "allowed in the app"),
        ActivityItem(age: "-1m", tone: 0, text: "The discount is applied twice, once in the reducer and once at checkout."),
        ActivityItem(age: "-2m", tone: 0, text: "Read src/cart/reducer.ts"),
        ActivityItem(age: "-3m", tone: 0, text: "You: the cart total is wrong when a coupon is used, can you fix it"),
      ]
    case "done":
      rows.insert(AgentRow(id: "d1", s: "done", a: "CX", n: "Codex", p: "design-tokens", d: "Migrated 214 tokens", age: 60), at: 0)
    case "idle":
      rows = [rows[2]]
    case "welcome":
      rows = []
    default:
      break
    }
    var pet = PetInfo(name: "Bit", total: 30, today: 5, age: 3, asleep: false)
    switch scene {
    case "pet-asleep": pet.asleep = true
    case "pet-birthday": pet.birthday = true
    case "pet-old": pet.age = 100
    case "pet-needs":
      pet.total = 200
      rows.insert(command, at: 0)
    default: break
    }
    if scene.hasPrefix("pet") {
      model.page = .pet
      if scene != "pet-work" { rows = rows.filter { $0.s != "working" } }
    }
    if scene == "pet-level" { model.petEvent = PetEvent(kind: .reward, at: Date(), turns: 2, levelUp: true) }
    if scene == "pet-birthday" { model.petEvent = PetEvent(kind: .birthday, at: Date()) }
    if scene == "pet-hello" { model.petEvent = PetEvent(kind: .welcome, at: Date()) }
    let connected = !["unplugged", "fw-write", "welcome", "noboard", "fw-unknown"].contains(scene)
    let flashState = ["fw-write": "flashing", "fw-back": "restarting", "fw-fail": "failed", "fw-core-read": "reading"][scene] ?? "idle"
    model.status = scene == "stopped" ? nil : DaemonStatus(
      pid: 4242, s: rows, pet: pet,
      board: BoardInfo(
        connected: connected, port: connected ? "/dev/cu.usbmodem1101" : nil,
        fw: !connected || scene == "fw-back" ? nil : scene.hasPrefix("fw-custom") ? "my-lamp-1.0" : "0.6.1",
        approves: scene == "fw-custom-on", label: scene.hasPrefix("fw-core") ? "desk cat" : nil, outdated: scene == "fw-custom-old",
        silent: scene == "fw-unknown" ? ["/dev/cu.usbmodem1101"] : []),
      machines: [MachineInfo(host: "studio", up: true, answers: true)],
      flash: FlashInfo(
        state: flashState, pct: 62, msg: scene == "fw-fail" ? "Couldn't reach the board. Hold BOOT while you plug it in, then try again." : "",
        to: scene == "fw-core-read" ? "custom-0.10.1-896b3059" : "0.6.2", tool: true, job: scene == "fw-core-read" ? "read" : "write"),
      core: Self.previewCore(scene))
    if scene.hasPrefix("fw") {
      model.page = .setup
      model.firmwareImage = FirmwareImage(version: "0.6.2")
    } else {
      model.firmwareImage = FirmwareImage(version: "0.6.1")
    }
    if scene.hasPrefix("fw-core") { model.status?.board.fw = "custom-0.10.1-896b3059" }
    model.firmwarePlan = FirmwarePlan.make(
      status: model.status, image: model.firmwareImage)
    if scene.hasPrefix("setup") { model.page = .setup }
    model.pinAsk()
    if scene == "stopped" { model.problem = "daemon stopped: ModuleNotFoundError" }

    if scene == "setup-short" { model.maxPanelHeight = 420 }
    Extensions.preview?(scene, model)

    // Hosted in a real (offscreen) window: ImageRenderer can't draw scroll views or text fields.
    let host = NSHostingView(rootView: PanelView().environmentObject(model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 2000), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 2000)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.9))  // past the buttons' arm delay
    let measured = NSSize(width: panelWidth, height: model.panelHeight > 0 ? model.panelHeight : 400)
    window.setContentSize(measured)
    host.frame = NSRect(origin: .zero, size: measured)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      print("preview: nothing rendered")
      exit(1)
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }

  /// fw-core: an update to offer; -new: not registered; -again: runs a build this Mac has no copy of;
  /// -read: reading what it runs, to register it; -blocked: needs the folder changed;
  /// -build, -write, -back: under way; -fail: the new build didn't start.
  static func previewCore(_ scene: String) -> CoreInfo? {
    guard scene.hasPrefix("fw-core") else { return nil }
    var core = CoreInfo(registered: !["fw-core-new", "fw-core-again", "fw-core-read"].contains(scene), core: "0.10.1", available: "0.11.0")
    switch scene {
    case "fw-core-again": core.folder = "/Users/you/boards/desk-cat"
    case "fw-core-blocked": core.blocked = "This update needs the board's folder changed. Ask Claude to update it."
    case "fw-core-build": (core.state, core.pct, core.to) = ("building", 37, "0.11.0")
    case "fw-core-write": (core.state, core.to) = ("writing", "0.11.0")
    case "fw-core-back": (core.state, core.to) = ("putting-back", "0.11.0")
    case "fw-core-fail":
      core.state = "failed"
      core.msg = "The new build didn't work, so custom-0.10.1-896b3059 went back on. (the board didn't come back after writing)"
    default: break
    }
    return core
  }
}
