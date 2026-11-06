import Foundation
import Testing
@testable import TTYCat

private func status(fw: String?, connected: Bool = true, state: String = "idle", tool: Bool = true, flash: Bool = true,
                    name: String? = "this-board", outdated: Bool = false, silent: [String] = [], probing: Bool = false) -> DaemonStatus {
  DaemonStatus(
    pid: 1, s: [], pet: nil,
    board: BoardInfo(connected: connected, port: connected ? "/dev/cu.usbmodem1101" : nil, fw: fw, name: name, outdated: outdated, silent: silent, probing: probing),
    machines: [],
    flash: flash ? FlashInfo(state: state, pct: 40, msg: "", to: "0.7.0", tool: tool) : nil)
}

private let image = FirmwareImage(version: "0.7.0", board: "this-board")

private func plan(_ s: DaemonStatus?, image i: FirmwareImage? = image) -> FirmwarePlan {
  FirmwarePlan.make(status: s, image: i)
}

@Test func versionsCompareByNumber() {
  #expect(FirmwareVersion.isNewer("0.10.0", than: "0.9.1") == true)
  #expect(FirmwareVersion.isNewer("0.6.1", than: "0.6.1") == false)
  #expect(FirmwareVersion.isNewer("0.6", than: "0.6.1") == false)
  #expect(FirmwareVersion.isNewer("1.0.0", than: "0.9.9") == true)
  #expect(FirmwareVersion.isNewer("dev", than: "0.6.1") == nil)
}

@Test func anOlderBoardIsOfferedTheUpdate() {
  #expect(plan(status(fw: "0.6.1")) == .update(from: "0.6.1", to: "0.7.0"))
  #expect(plan(status(fw: "0.6.1")).wantsAttention)
}

@Test func theSameVersionNeedsNothing() {
  #expect(plan(status(fw: "0.7.0")) == .upToDate("0.7.0"))
  #expect(!plan(status(fw: "0.7.0")).wantsAttention)
}

@Test func aNewerBoardIsNeverDowngraded() {
  #expect(plan(status(fw: "0.8.0")) == .boardNewer(board: "0.8.0", app: "0.7.0"))
}

@Test func customFirmwareIsNeverOfferedAnUpdate() {
  let lamp = FirmwarePlan.customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: true, outdated: false)
  #expect(plan(status(fw: "my-lamp-1.0")) == lamp)
  #expect(!plan(status(fw: "my-lamp-1.0")).wantsAttention)
  #expect(plan(status(fw: "dev")) == .customFirmware(name: "dev", port: "cu.usbmodem1101", canReplace: true, outdated: false))
  #expect(plan(status(fw: "my-lamp-1.0", tool: false)) == .customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: false, outdated: false))
}

@Test func firmwareForAnotherBoardIsNeverOffered() {
  for other in ["another-board", nil] as [String?] {
    #expect(plan(status(fw: "my-lamp-1.0", name: other)) == .customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: false, outdated: false))
  }
}

@Test func anOutdatedPortIsToldSo() {
  #expect(plan(status(fw: "my-lamp-1.0", outdated: true)) == .customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: true, outdated: true))
}

@Test func onlyPlainVersionsAreOurs() {
  for ours in ["0.9.1", "1", "0.10.0"] { #expect(!FirmwareVersion.isCustom(ours)) }
  for theirs in ["custom-0.9.1-7e297979", "my-lamp-1.0", "dev", "0.9.1-mine", "1..2", "+1.2", ""] { #expect(FirmwareVersion.isCustom(theirs)) }
}

@Test func aPortOnlyCountsAsUnknownOnceItsHadItsChance() {
  #expect(plan(status(fw: nil, connected: false, probing: true)) == .identifying)
  #expect(plan(status(fw: nil, connected: false, silent: ["/dev/cu.usbmodem1101"])) == .unknownDevice(port: "/dev/cu.usbmodem1101"))
  #expect(plan(status(fw: nil, connected: false, tool: false, silent: ["/dev/cu.usbmodem1101"])) == .noTool(to: "0.7.0"))
}

@Test func nothingToOfferWithoutImageBoardOrTool() {
  #expect(plan(status(fw: "0.6.1"), image: nil) == .noImage)
  #expect(plan(status(fw: nil, connected: false)) == .notConnected)
  #expect(plan(nil) == .notConnected)
  #expect(plan(status(fw: "0.6.1", tool: false)) == .noTool(to: "0.7.0"))
  #expect(plan(status(fw: "0.6.1", flash: false)) == .daemonTooOld)
}

@Test func progressComesFirstWhileUpdating() {
  #expect(plan(status(fw: nil, connected: false, state: "flashing")) == .writing(pct: 40, to: "0.7.0"))
  #expect(plan(status(fw: nil, state: "restarting")) == .restarting(to: "0.7.0"))
}

@Test func afterAFailureTheOfferIsBack() {
  #expect(plan(status(fw: "0.6.1", state: "failed")) == .update(from: "0.6.1", to: "0.7.0"))
}

private func withCore(_ core: CoreInfo, flash state: String = "idle") -> DaemonStatus {
  var s = status(fw: "custom-0.10.1-896b3059", state: state)
  s.core = core
  return s
}

@Test func aRegisteredBoardIsOfferedTheNewCore() {
  let core = CoreInfo(registered: true, core: "0.10.1", available: "0.11.0")
  let p = plan(withCore(core))
  #expect(p == .customFirmware(name: "custom-0.10.1-896b3059", port: "cu.usbmodem1101", canReplace: true, outdated: false, core: core))
  #expect(p.wantsAttention)
}

@Test func aCoreThatCantBeBuiltYetIsntPushed() {
  for core in [CoreInfo(registered: true, core: "0.10.1", available: "0.11.0", blocked: "needs ESP-IDF 6.0"),
               CoreInfo(registered: false, core: "0.10.1", available: "0.11.0"),
               CoreInfo(registered: true, core: "0.11.0")] {
    #expect(!core.canUpdate)
    #expect(!plan(withCore(core)).wantsAttention)
  }
}

@Test func aCoreUpdateShowsEachStep() {
  var core = CoreInfo(registered: true, core: "0.10.1", available: "0.11.0", state: "building", pct: 37, to: "0.11.0")
  #expect(plan(withCore(core)) == .coreUpdate(step: .building, pct: 37, to: "0.11.0"))
  core.state = "writing"
  #expect(plan(withCore(core, flash: "flashing")) == .coreUpdate(step: .writing, pct: 40, to: "0.11.0"))
  #expect(plan(withCore(core, flash: "restarting")) == .coreUpdate(step: .restarting, pct: 40, to: "0.11.0"))
  core.state = "putting-back"
  #expect(plan(withCore(core, flash: "flashing")) == .coreUpdate(step: .puttingBack, pct: 40, to: "0.11.0"))
  core.state = "failed"
  #expect(!core.busy)
}

@Test func coreInfoReadsWhatTheDaemonSends() throws {
  let json = #"{"registered":true,"core":"0.10.1","available":"0.11.0","blocked":"","state":"idle","pct":0,"msg":"","to":null}"#
  let core = try JSONDecoder().decode(CoreInfo.self, from: Data(json.utf8))
  #expect(core.canUpdate)
}

@Test func aBoardOfOnesOwnNeedsNoImageInTheApp() {
  var s = status(fw: "custom-0.10.2-62d06270")
  s.core = CoreInfo(registered: true, core: "0.10.2", available: "0.10.3")
  #expect(plan(s, image: nil) == .customFirmware(name: "custom-0.10.2-62d06270", port: "cu.usbmodem1101", canReplace: false,
                                                  outdated: false, core: s.core))
  #expect(plan(s, image: nil).wantsAttention)
  #expect(plan(status(fw: "0.6.1"), image: nil) == .noImage)
  #expect(plan(nil, image: nil) == .noImage)
}

@Test func theSignedReleaseIsWhatTheAppShows() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try #"{"version":"0.9.0","board":"this-board"}"#.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
  #expect(FirmwareImage.read(folder.path)?.version == "0.9.0")
  let body = #"{\"version\":\"0.11.0\",\"board\":\"this-board\",\"kind\":\"ttycat-firmware\"}"#
  try #"{"body":"\#(body)","key":"k","sig":"s"}"#.write(to: folder.appendingPathComponent("release.json"), atomically: true, encoding: .utf8)
  #expect(FirmwareImage.read(folder.path)?.version == "0.11.0")
}
