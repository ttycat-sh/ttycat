// The app updating itself, with Sparkle. Only a release does: one with build.json in its daemon folder
// (tools/app_build.py) and SUPublicEDKey in its Info.plist. A developer's build never starts it.
//
// Sparkle asks the feed in build.json, ttycat's update server, with the install ID the daemon keeps
// (for rollouts) and the build it runs (for the count). It installs only a disk image signed by the app
// update key in SUPublicEDKey, holding an app signed by the same Developer ID team as this one.
import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject {
  struct BuildInfo: Decodable {
    let release: Bool
    let env: String?
    let version: String?
    let appcast: String?
  }

  /// The release this app is, or nil for a developer's build.
  static let build: BuildInfo? = {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("daemon/build.json"),
          let data = try? Data(contentsOf: url),
          let info = try? JSONDecoder().decode(BuildInfo.self, from: data), info.release
    else { return nil }
    return info
  }()

  /// As people read it: 0.2.0-dev.1, or "developer build".
  static var version: String {
    build?.version ?? (Bundle.main.object(forInfoDictionaryKey: "TTYCatVersion") as? String) ?? "developer build"
  }

  private var controller: SPUStandardUpdaterController?
  /// A newer app Sparkle found on its own schedule, waiting for the person: Setup shows it.
  var ready: ((String?) -> Void)?

  var isActive: Bool { controller != nil }

  /// Starts checking on Sparkle's schedule, if this is a release. Off when the person turned update
  /// checks off in Setup: the same setting as the board's.
  func start(checking: Bool) {
    guard controller == nil, let build = Self.build, build.appcast != nil,
          Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
    else { return }
    let made = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    made.updater.automaticallyChecksForUpdates = checking
    do {
      try made.updater.start()
    } catch {
      NSLog("ttycat: the app's updater didn't start: \(error.localizedDescription)")
      return
    }
    controller = made
  }

  func setChecking(_ on: Bool) {
    controller?.updater.automaticallyChecksForUpdates = on
  }

  /// The person asked: Sparkle's own window says what it found.
  func check() {
    guard let controller else { return }
    NSApp.activate()
    controller.checkForUpdates(nil)
  }
}

extension AppUpdater: SPUUpdaterDelegate {
  nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
    MainActor.assumeIsolated { Self.build?.appcast }
  }

  /// Only these, and never Sparkle's system profile.
  nonisolated func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
    var parameters: [[String: String]] = []
    let idFile = URL(fileURLWithPath: NSHomeDirectory() + "/.ttycat/install-id")
    if let id = try? String(contentsOf: idFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       id.count == 32, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
      parameters.append(["key": "install", "value": id, "displayKey": "Install", "displayValue": id])
    }
    if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
      parameters.append(["key": "build", "value": build, "displayKey": "Build", "displayValue": build])
    }
    return parameters
  }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
  // A menu bar app: Sparkle doesn't put its window in front of what you're doing on a schedule.
  // Setup shows the update instead, and a notification says so. Asking for it shows the window.
  nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

  nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    immediateFocus
  }

  nonisolated func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    let version = update.displayVersionString
    MainActor.assumeIsolated {
      if !handleShowingUpdate { ready?(version) }
    }
  }

  nonisolated func standardUserDriverWillFinishUpdateSession() {
    MainActor.assumeIsolated { ready?(nil) }
  }
}
