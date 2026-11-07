// What an extended build can add to the app. The open-source build adds nothing, and runs fine.
// Everything an extension can reach through here is the contract between the two: change it, and
// bump apiVersion, as with daemon/plugins.py.
import SwiftUI

struct ExtraPage {
  let id: String
  let title: String
  let view: @MainActor () -> AnyView
}

@MainActor
enum Extensions {
  static let apiVersion = 1
  static var pages: [ExtraPage] = []
  static var setupSections: [@MainActor () -> AnyView] = []
  static var started: [@MainActor (TTYCatModel) -> Void] = []
  static var polled: [@MainActor (TTYCatModel) -> Void] = []  // once a second
  /// Uninstalling: take away what the extension added outside the app. Run before the daemon stops.
  static var uninstalling: [@MainActor (TTYCatModel) -> Void] = []
  static var preview: (@MainActor (String, TTYCatModel) -> Void)?

  /// Called once, before anything starts. A build with extensions compiles its own in.
  static func install() {
    #if TTYCAT_PRO
    ProFeatures.install()
    #endif
  }
}
