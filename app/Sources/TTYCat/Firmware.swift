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
  var board: String? = nil

  static var folder: String? { Bundle.main.resourceURL?.appendingPathComponent("firmware").path }

  static func inApp() -> FirmwareImage? {
    guard let folder else { return nil }
    return read(folder)
  }

  /// What an image says it is: from its signed release.json if it has one, as the daemon reads it.
  /// Only for showing: the daemon checks the signature before writing anything.
  static func read(_ folder: String) -> FirmwareImage? {
    struct Signed: Decodable { let body: String }
    if let data = FileManager.default.contents(atPath: folder + "/release.json") {
      guard let signed = try? JSONDecoder().decode(Signed.self, from: data) else { return nil }
      return try? JSONDecoder().decode(FirmwareImage.self, from: Data(signed.body.utf8))
    }
    guard let data = FileManager.default.contents(atPath: folder + "/manifest.json") else { return nil }
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

  /// ttycat's firmware gives a plain version. Anything else is someone's own, and isn't ours to replace.
  static func isCustom(_ fw: String) -> Bool {
    !fw.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
      !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
    }
  }
}

enum FirmwarePlan: Equatable {
  case noImage                    // this build of the app carries none
  case daemonTooOld               // running a daemon from before this existed
  case notConnected
  case identifying                // just connected: it says what it runs within seconds
  case unknownDevice(port: String)  // a port that doesn't answer: could be any device
  case customFirmware(name: String, port: String, canReplace: Bool, outdated: Bool, core: CoreInfo? = nil)  // someone's own: only ever updated from its own folder
  case coreUpdate(step: CoreStep, pct: Int, to: String)  // building a new core for someone's own board, and putting it on
  case upToDate(String)
  case boardNewer(board: String, app: String)
  case update(from: String, to: String)
  case noTool(to: String)
  case writing(pct: Int, to: String)
  case restarting(to: String)

  static func make(status: DaemonStatus?, image: FirmwareImage?) -> FirmwarePlan {
    // A board of someone's own is updated from its own folder, so it doesn't need the image this app carries.
    guard let status, let flash = status.flash else {
      return image == nil ? .noImage : status == nil ? .notConnected : .daemonTooOld
    }
    if let core = status.core, core.busy {
      let to = core.to ?? "the new core"
      switch core.state {
      case "building": return .coreUpdate(step: .building, pct: core.pct, to: to)
      case "writing": return .coreUpdate(step: flash.state == "restarting" ? .restarting : .writing, pct: flash.pct, to: to)
      default: return .coreUpdate(step: .puttingBack, pct: flash.pct, to: to)
      }
    }
    if status.board.connected, let port = status.board.port, let fw = status.board.fw, FirmwareVersion.isCustom(fw),
       !flash.busy {
      // Firmware for another board would leave this one with a dark screen, even on the same chip.
      let fits = image?.board != nil && image?.board == status.board.name
      return .customFirmware(name: fw, port: (port as NSString).lastPathComponent, canReplace: flash.tool && fits,
                             outdated: status.board.outdated == true, core: status.core)
    }
    guard let image else { return .noImage }
    if flash.state == "flashing" { return .writing(pct: flash.pct, to: flash.to ?? image.version) }
    if flash.state == "restarting" { return .restarting(to: flash.to ?? image.version) }
    guard status.board.connected, status.board.port != nil, let fw = status.board.fw else {
      if status.board.probing == true { return .identifying }
      guard let silent = status.board.silent?.first else { return .notConnected }
      return flash.tool ? .unknownDevice(port: silent) : .noTool(to: image.version)
    }
    if fw == image.version { return .upToDate(fw) }
    if FirmwareVersion.isNewer(fw, than: image.version) == true { return .boardNewer(board: fw, app: image.version) }
    return flash.tool ? .update(from: fw, to: image.version) : .noTool(to: image.version)
  }

  /// Worth pointing out on the Setup tab.
  var wantsAttention: Bool {
    switch self {
    case .update, .unknownDevice: return true
    case .customFirmware(_, _, _, _, let core): return core?.canUpdate == true
    default: return false
    }
  }
}

enum CoreStep: Equatable {
  case building, writing, restarting, puttingBack
}
