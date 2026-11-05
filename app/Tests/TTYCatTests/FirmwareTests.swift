import Testing
@testable import TTYCat

private func status(fw: String?, connected: Bool = true, state: String = "idle", tool: Bool = true, flash: Bool = true) -> DaemonStatus {
  DaemonStatus(
    pid: 1, s: [], pet: nil,
    board: BoardInfo(connected: connected, port: connected ? "/dev/cu.usbmodem1101" : nil, fw: fw),
    machines: [],
    flash: flash ? FlashInfo(state: state, pct: 40, msg: "", to: "0.7.0", tool: tool) : nil)
}

private let image = FirmwareImage(version: "0.7.0")

private func plan(_ s: DaemonStatus?, image i: FirmwareImage? = image, silent: Double = 0) -> FirmwarePlan {
  FirmwarePlan.make(status: s, image: i, silent: silent)
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
  let lamp = FirmwarePlan.customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: true)
  #expect(plan(status(fw: "my-lamp-1.0")) == lamp)
  #expect(!plan(status(fw: "my-lamp-1.0")).wantsAttention)
  #expect(plan(status(fw: "dev")) == .customFirmware(name: "dev", port: "cu.usbmodem1101", canReplace: true))
  #expect(plan(status(fw: "my-lamp-1.0", tool: false)) == .customFirmware(name: "my-lamp-1.0", port: "cu.usbmodem1101", canReplace: false))
}

@Test func onlyPlainVersionsAreOurs() {
  for ours in ["0.9.1", "1", "0.10.0"] { #expect(!FirmwareVersion.isCustom(ours)) }
  for theirs in ["my-lamp-1.0", "dev", "0.9.1-mine", "1..2", "+1.2", ""] { #expect(FirmwareVersion.isCustom(theirs)) }
}

@Test func aSilentPortGetsTimeBeforeItCountsAsUnknown() {
  #expect(plan(status(fw: nil), silent: 3) == .identifying)
  #expect(plan(status(fw: nil), silent: 9) == .unknownDevice(port: "cu.usbmodem1101"))
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
