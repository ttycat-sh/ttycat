// Offering to move the app into Applications, the first thing a release does when it's opened from
// anywhere else. Sparkle replaces the app where it is: it can't on the disk image, and macOS runs an app
// opened from Downloads from a hidden, read-only copy (App Translocation). A developer's build never asks.
import AppKit
import Darwin

@MainActor
enum AppMover {
  /// A release that isn't in Applications yet.
  static var shouldOffer: Bool {
    let app = Bundle.main.bundleURL
    return AppUpdater.build != nil && !isInApplications(untranslocated(app) ?? app)
  }

  nonisolated static func isInApplications(_ app: URL, home: String = NSHomeDirectory()) -> Bool {
    let path = app.standardizedFileURL.resolvingSymlinksInPath().path
    return ["/Applications/", home + "/Applications/"].contains { path.hasPrefix($0) }
  }

  /// Where it goes: /Applications, or ~/Applications for someone who can't write there.
  nonisolated static func destination(for app: URL, home: String = NSHomeDirectory(),
                                      writable: (String) -> Bool = FileManager.default.isWritableFile) -> URL {
    let folder = writable("/Applications") ? "/Applications" : home + "/Applications"
    return URL(fileURLWithPath: folder).appendingPathComponent(app.lastPathComponent)
  }

  /// At launch. True when it's moving: the app quits, and opens again from Applications.
  static func offerAtLaunch() -> Bool {
    guard shouldOffer else { return false }
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Move ttycat to Applications?"
    alert.informativeText = "It can only update itself from there. It opens again by itself, from Applications."
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Not Now")
    guard alert.runModal() == .alertFirstButtonReturn else { return false }
    return move()
  }

  /// Copies it into Applications, puts the copy it was opened from in the Trash (or ejects the disk
  /// image it's on), and opens the new one once this has quit. Says so if it can't.
  @discardableResult
  static func move() -> Bool {
    StatusPanel.shared?.close()  // it sits above other windows, such as an alert that it couldn't
    let fm = FileManager.default
    let running = Bundle.main.bundleURL
    let original = untranslocated(running)  // nil: macOS didn't say where it really is
    let target = destination(for: running)
    do {
      try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      if fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: nil) }
      try fm.copyItem(at: running, to: target)
    } catch {
      NSApp.activate()
      let alert = NSAlert()
      alert.messageText = "ttycat couldn't move itself"
      alert.informativeText = "\(error.localizedDescription)\n\nQuit it, and drag it into Applications in the Finder instead."
      alert.runModal()
      return false
    }
    // The same app the person just chose to open, which Gatekeeper has checked: it shouldn't ask again.
    run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
    let image = original.flatMap(diskImage)
    if image == nil, let original, fm.isWritableFile(atPath: original.deletingLastPathComponent().path) {
      try? fm.trashItem(at: original, resultingItemURL: nil)  // so the old copy isn't opened by mistake
    }
    // Once this one has quit: there can only be one ttycat running.
    let script = """
      while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
      [ -n "$2" ] && /usr/bin/hdiutil detach -quiet "$2"
      /usr/bin/open "$1"
      """
    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
    relaunch.arguments = ["-c", script, "sh", target.path, image ?? ""]
    do { try relaunch.run() } catch { return false }
    NSApp.terminate(nil)
    return true
  }

  /// Where an app macOS translocated really is, from Security.framework's own answer.
  nonisolated static func untranslocated(_ app: URL) -> URL? {
    guard app.path.contains("/AppTranslocation/") else { return app }
    typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
    guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
          let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
    else { return nil }
    let original = unsafeBitCast(symbol, to: Original.self)
    return original(app as CFURL, nil)?.takeRetainedValue() as URL?
  }

  /// The mount point of the disk image the app is on, if it's on one: never any other drive.
  nonisolated static func diskImage(_ app: URL) -> String? {
    guard app.path.hasPrefix("/Volumes/"),
          let out = run("/usr/bin/hdiutil", ["info", "-plist"]),
          let info = try? PropertyListSerialization.propertyList(from: out, format: nil) as? [String: Any]
    else { return nil }
    return mountPoint(of: app.path, in: info)
  }

  nonisolated static func mountPoint(of path: String, in info: [String: Any]) -> String? {
    let images = info["images"] as? [[String: Any]] ?? []
    let points = images.flatMap { ($0["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["mount-point"] as? String } }
    return points.first { path.hasPrefix($0 + "/") }
  }

  @discardableResult
  nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
  }
}
