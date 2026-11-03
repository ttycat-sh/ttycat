// Whether the board's firmware needs anything, and what to offer. No side effects: all testable.
import Foundation

struct FlashInfo: Decodable {
  var state: String  // idle | flashing | restarting | done | failed
  var pct: Int
  var msg: String
  var to: String?
  var tool: Bool     // esptool was found

  var busy: Bool { state == "flashing" || state == "restarting" }
}

/// The firmware this copy of the app carries: app/build.sh packs it from firmware/build.
struct FirmwareImage: Decodable {
  let version: String

  static var folder: String? { Bundle.main.resourceURL?.appendingPathComponent("firmware").path }

  static func inApp() -> FirmwareImage? {
    guard let folder, let data = FileManager.default.contents(atPath: folder + "/manifest.json") else { return nil }
    return try? JSONDecoder().decode(FirmwareImage.self, from: data)
  }
}

enum FirmwareVersion {
  /// Number by number, so 0.10.0 is newer than 0.9.1. Nil if either isn't plain numbers.
  static func isNewer(_ a: String, than b: String) -> Bool? {
    func parts(_ s: String) -> [Int]? {
      let split = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
      return split.contains { $0 == nil } ? nil : split.compactMap { $0 }
    }
    guard let x = parts(a), let y = parts(b) else { return nil }
    for i in 0..<max(x.count, y.count) {
      let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
      if p != q { return p > q }
    }
    return false
  }
}

enum FirmwarePlan: Equatable {
  case noImage                    // this build of the app carries none
  case daemonTooOld               // running a daemon from before this existed
  case notConnected
  case identifying                // just connected: it says what it runs within seconds
  case unknownDevice(port: String)  // a port that doesn't answer: could be any device
  case upToDate(String)
  case boardNewer(board: String, app: String)
  case update(from: String, to: String)
  case noTool(to: String)
  case writing(pct: Int, to: String)
  case restarting(to: String)

  /// `silent`: how long the port has been open without the board saying what it runs.
  static func make(status: DaemonStatus?, image: FirmwareImage?, silent: TimeInterval) -> FirmwarePlan {
    guard let image else { return .noImage }
    guard let status else { return .notConnected }
    guard let flash = status.flash else { return .daemonTooOld }
    if flash.state == "flashing" { return .writing(pct: flash.pct, to: flash.to ?? image.version) }
    if flash.state == "restarting" { return .restarting(to: flash.to ?? image.version) }
    guard status.board.connected, let port = status.board.port else { return .notConnected }
    guard let fw = status.board.fw else {
      if silent < unknownAfter { return .identifying }
      return flash.tool ? .unknownDevice(port: (port as NSString).lastPathComponent) : .noTool(to: image.version)
    }
    if fw == image.version { return .upToDate(fw) }
    if FirmwareVersion.isNewer(fw, than: image.version) == true { return .boardNewer(board: fw, app: image.version) }
    return flash.tool ? .update(from: fw, to: image.version) : .noTool(to: image.version)
  }

  static let unknownAfter: TimeInterval = 8

  /// Worth pointing out on the Setup tab.
  var wantsAttention: Bool {
    switch self {
    case .update, .unknownDevice: return true
    default: return false
    }
  }
}
