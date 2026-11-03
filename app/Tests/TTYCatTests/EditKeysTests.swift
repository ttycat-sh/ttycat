import AppKit
import Testing

@testable import TTYCat

@Suite struct EditingKeys {
  @Test func theUsualOnes() {
    #expect(EditKeys.action(key: "v", flags: .command) == #selector(NSText.paste(_:)))
    #expect(EditKeys.action(key: "c", flags: .command) == #selector(NSText.copy(_:)))
    #expect(EditKeys.action(key: "x", flags: .command) == #selector(NSText.cut(_:)))
    #expect(EditKeys.action(key: "a", flags: .command) == #selector(NSText.selectAll(_:)))
    #expect(EditKeys.action(key: "z", flags: .command) == Selector(("undo:")))
    #expect(EditKeys.action(key: "z", flags: [.command, .shift]) == Selector(("redo:")))
  }

  @Test func capsLockAndTheNumberPadDontGetInTheWay() {
    #expect(EditKeys.action(key: "V", flags: [.command, .capsLock]) == #selector(NSText.paste(_:)))
    #expect(EditKeys.action(key: "v", flags: [.command, .numericPad]) == #selector(NSText.paste(_:)))
  }

  @Test func anythingElseIsLeftAlone() {
    #expect(EditKeys.action(key: "v", flags: []) == nil)
    #expect(EditKeys.action(key: "v", flags: [.command, .option]) == nil)
    #expect(EditKeys.action(key: "q", flags: .command) == nil)
    #expect(EditKeys.action(key: nil, flags: .command) == nil)
  }
}
