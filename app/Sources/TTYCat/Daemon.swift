// The Python daemon: keeping it running, and talking to it over its control socket.
import Darwin
import Foundation

struct AgentRow: Decodable, Identifiable {
  let id: String
  let s: String
  var a: String?
  var n: String?
  var p: String?
  var d: String?
  var host: String?
  var tool: String?
  var age: Double?
  // A prompt, when it's blocked:
  var verb: String?
  var body: String?
  var rev: String?
  var ask: String?   // approve | choice | terminal
  var note: String?
  var file: String?
  var add: Int?
  var del: Int?
  var qs: [Question]?
  // For notifications:
  var foc: Bool?     // its pane is the one focused in herdr
  var said: String?  // the last thing it said this turn

  var needsYou: Bool { s == "blocked" || s == "error" }
  var canOpen: Bool { a != "--" }  // the row for a machine that can't be reached
}

struct QuestionOption: Decodable {
  let l: String
  let d: String
}

struct Question: Decodable {
  let q: String
  let m: Bool
  let o: [QuestionOption]
}

struct ActivityItem: Decodable {
  let age: String
  let tone: Int
  let text: String
}

struct ActivityReply: Decodable {
  let items: [ActivityItem]
}

struct PetInfo: Decodable {
  var name: String
  var total: Int
  var today: Int
  var age: Int
  var asleep: Bool
  var birthday = false
  var ev: Int?     // numbers the latest reaction, from here or the board, so each is shown once
  var evk: String? // what it looks like: heart, rested, welcome, birthday, or empty
  var grown: Int?  // what its level comes from: time, and tokens

  var level: Int { Self.level(total: grown ?? total) }

  // The same curve as firmware/main/pet.c.
  static func level(total: Int) -> Int {
    var n = 1
    while 3 * n * n <= total { n += 1 }
    return n
  }
}

struct BoardInfo: Decodable {
  var connected: Bool
  var port: String?
  var fw: String?
  var dim: Bool?  // its screen is dim, and Bit dozes there
  var approves: Bool?  // it may say yes to prompts: see daemon/devices.py
  var name: String?  // which folder in firmware/boards it was built from
  var label: String?  // the name the person gave it, kept on the board and on this Mac
  var outdated: Bool?  // it speaks another version of the protocol, so it's not being sent anything
  var silent: [String]?  // ports that were tried and said nothing
  var probing: Bool?  // trying one now
  var asks: Int?  // times it's asked for a prompt to be shown here
  var asked: String?
}

struct MachineInfo: Decodable {
  var host: String
  var up: Bool
  var answers: Bool?  // its tunnel is up: prompts there can be answered from here
}

struct DaemonStatus: Decodable {
  var pid: Int32
  var s: [AgentRow]
  var pet: PetInfo?
  var board: BoardInfo
  var machines: [MachineInfo]
  var term: String?  // the terminal app agents run in
  var flash: FlashInfo?  // nil from a daemon older than firmware updates
  var look: LookInfo?
  var core: CoreInfo?  // nil from a daemon older than core updates
  var updates: UpdatesInfo?  // nil from a daemon older than the update check
}

/// The daemon's check with ttycat's update server: daemon/updates.py.
struct UpdatesInfo: Decodable, Equatable {
  var check: Bool  // the setting: off, it never asks
  var checked: Double?  // when it last got an answer
  var error: String = ""
  var firmware: Downloaded?  // newer firmware for the official board that's connected, downloaded and checked

  struct Downloaded: Decodable, Equatable {
    var version: String
    var dir: String
  }
}

/// New core releases for a board of the person's own, built on this Mac with their folder: daemon/core_update.py.
struct CoreInfo: Decodable, Equatable {
  var registered: Bool  // its folder is known, and this Mac has a copy of what it runs, so the app can build for it
  var folder: String? = nil  // the folder registered for it last, even if it runs another build now
  var core: String?  // the release its build was made from
  var available: String?  // a newer signed release
  var blocked: String = ""  // why that one can't be built for it yet
  var state: String = "idle"  // idle | building | writing | putting-back | done | failed
  var pct: Int = 0
  var msg: String = ""
  var to: String?

  var busy: Bool { ["building", "writing", "putting-back"].contains(state) }
  /// Worth a button: there's a newer release, and nothing stands in its way.
  var canUpdate: Bool { registered && available != nil && blocked.isEmpty }
}

enum Ctl {
  static let path = NSHomeDirectory() + "/.ttycat/ctl.sock"

  /// One request, one reply. nil if the daemon isn't there. Blocks: call off the main thread.
  static func request(_ object: [String: Any], timeout: Int = 3) -> Data? {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return send(body, timeout: timeout)
  }

  static func send(_ body: Data, timeout: Int = 3) -> Data? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var wait = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else { return nil }
    var sent = 0
    while sent < body.count {  // a long typed answer can take more than one write
      let n = body.withUnsafeBytes { write(fd, $0.baseAddress! + sent, body.count - sent) }
      if n <= 0 { return nil }
      sent += n
    }

    var reply = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      let n = read(fd, &buffer, buffer.count)
      if n < 0 { return nil }
      if n == 0 { return reply }
      reply.append(buffer, count: n)
    }
  }
}

/// Keeps one daemon running. One that's already there (started in a terminal, or left over
/// from a crash) is used as it is: the daemon itself refuses to run twice.
final class Supervisor: @unchecked Sendable {  // only hook() runs off the main thread; it touches nothing that changes
  private static let alreadyRunning: Int32 = 3
  // A menu bar app gets a minimal PATH: without this neither herdr nor Homebrew's Python is found.
  static let searchPath =
    "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  static let logPath = NSHomeDirectory() + "/.ttycat/ttycatd.log"

  private(set) var child: Process?
  private var failures = 0
  private var nextStart = Date.distantPast
  private var expectingExit = false
  private(set) var problem: String?
  // From an extension, before the daemon starts: see Extensions.swift and daemon/plugins.py.
  var globalArguments: [String] = []
  var runArguments: [String] = []

  /// In the app. TTYCAT_DAEMON_DIR runs it from a checkout instead, while working on it.
  let daemonDir = ProcessInfo.processInfo.environment["TTYCAT_DAEMON_DIR"]
    ?? Bundle.main.resourceURL?.appendingPathComponent("daemon").path

  /// The app's own, from app/vendor.sh: a Mac may have no other. A build without it uses the system's.
  static var python: String? {
    let own = Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3").path
    return ([own].compactMap { $0 } + ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"])
      .first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// Only what's in the app: nothing set in your shell or installed for your user gets loaded.
  /// Nothing's written beside the code either: the app is signed.
  private static let pythonFlags = ["-E", "-s", "-B"]

  var script: String? {
    guard let daemonDir else { return nil }
    let path = daemonDir + "/ttycatd.py"
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }

  func ownsDaemon(pid: Int32) -> Bool { child?.isRunning == true && child?.processIdentifier == pid }

  /// Once a second. `heard`: the daemon answered just now.
  func tick(heard: Bool) {
    if heard {
      failures = 0
      problem = nil
      return
    }
    if child?.isRunning == true || Date() < nextStart { return }
    start()
  }

  private func start() {
    guard let python = Self.python else {
      problem = "no python3 found"
      return
    }
    guard script != nil, let daemonDir else {
      problem = "daemon folder not found: \(daemonDir ?? "not set")"
      return
    }
    guard let log = openLog() else {
      problem = "can't write \(Self.logPath)"
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: python)
    process.currentDirectoryURL = URL(fileURLWithPath: daemonDir)
    process.arguments = Self.pythonFlags + ["-u", "ttycatd.py"] + globalArguments + ["run"] + runArguments
    var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
    env["PATH"] = Self.searchPath
    process.environment = env
    process.standardOutput = log
    process.standardError = log
    process.standardInput = FileHandle.nullDevice
    process.terminationHandler = { [weak self] ended in
      DispatchQueue.main.async { self?.ended(ended) }
    }
    do {
      try process.run()
      child = process
    } catch {
      problem = "couldn't start python3: \(error.localizedDescription)"
      scheduleRetry()
    }
    try? log.close()
  }

  private func ended(_ process: Process) {
    guard child === process else { return }
    child = nil
    if expectingExit {
      expectingExit = false
      return
    }
    if process.terminationStatus == Self.alreadyRunning {
      problem = "another daemon has the board, and isn't answering"
    } else {
      problem = "daemon stopped: " + (lastLogLine() ?? "exit \(process.terminationStatus)")
    }
    scheduleRetry()
  }

  private func scheduleRetry() {
    failures += 1
    nextStart = Date().addingTimeInterval(min(pow(2, Double(failures)), 30))
  }

  /// Stops whichever daemon is running; `tick` then starts a new one with today's settings.
  func restart(runningPid: Int32?) {
    problem = nil
    failures = 0
    nextStart = Date().addingTimeInterval(3)  // quiet for over 2 s, the board says hello: that's its version
    if let child, child.isRunning {
      expectingExit = true
      child.terminate()
    } else if let runningPid {
      kill(runningPid, SIGTERM)
    }
  }

  /// A daemon this app started goes with it. One started elsewhere isn't ours to stop.
  func stopForQuit() {
    guard let child, child.isRunning else { return }
    expectingExit = true
    child.terminate()
    let deadline = Date().addingTimeInterval(1.5)
    while child.isRunning && Date() < deadline { usleep(20_000) }
  }

  private func openLog() -> FileHandle? {
    let fm = FileManager.default
    try? fm.createDirectory(
      atPath: NSHomeDirectory() + "/.ttycat", withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    // One old log is kept; it can't grow for ever.
    if let size = (try? fm.attributesOfItem(atPath: Self.logPath))?[.size] as? Int, size > 5_000_000 {
      try? fm.removeItem(atPath: Self.logPath + ".old")
      try? fm.moveItem(atPath: Self.logPath, toPath: Self.logPath + ".old")
    }
    if !fm.fileExists(atPath: Self.logPath) {
      fm.createFile(atPath: Self.logPath, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let log = FileHandle(forWritingAtPath: Self.logPath) else { return nil }
    _ = try? log.seekToEnd()
    return log
  }

  private func lastLogLine() -> String? {
    guard let log = FileHandle(forReadingAtPath: Self.logPath) else { return nil }
    defer { try? log.close() }
    let end = (try? log.seekToEnd()) ?? 0
    try? log.seek(toOffset: end > 400 ? end - 400 : 0)
    let text = String(decoding: log.readDataToEndOfFile(), as: UTF8.self)
    return text.split(separator: "\n").last.map(String.init)
  }

  /// `ttycatd.py hook …`: the daemon's code stays the only thing that edits Claude's settings.
  func hook(_ action: String) -> (ok: Bool, installed: Bool) { tool(["hook", action]) }

  /// One of the daemon's own commands, to its end. Off the main thread.
  func tool(_ arguments: [String]) -> (ok: Bool, installed: Bool) {
    guard let python = Self.python, let daemonDir, script != nil else { return (false, false) }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: python)
    process.currentDirectoryURL = URL(fileURLWithPath: daemonDir)
    process.arguments = Self.pythonFlags + ["ttycatd.py"] + globalArguments + arguments
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = Self.searchPath  // a menu bar app's PATH is minimal: ssh, for another machine
    process.environment = env
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return (false, false) }
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return (false, false) }
    return (true, text.contains(": installed"))
  }
}
