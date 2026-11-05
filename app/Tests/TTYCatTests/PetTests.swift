import Foundation
import Testing
@testable import TTYCat

private func row(_ s: String, id: String = "a", rev: String? = nil) -> AgentRow {
  AgentRow(id: id, s: s, a: "CC", n: "Claude", p: "shop", rev: rev)
}

@Test func promptsWaitForAMomentAfterAnInterruption() {
  let now = Date(timeIntervalSince1970: 1000)
  #expect(!HandsOff.clear(now: now, until: now.addingTimeInterval(0.1), lastClick: .distantPast))
  #expect(HandsOff.clear(now: now, until: now, lastClick: .distantPast))
}

@Test func promptsWaitWhileClicksKeepComing() {
  let now = Date(timeIntervalSince1970: 1000)
  #expect(!HandsOff.clear(now: now, until: .distantPast, lastClick: now.addingTimeInterval(-0.5)))
  #expect(HandsOff.clear(now: now, until: .distantPast, lastClick: now.addingTimeInterval(-0.81)))
}

@Test func aDifferentPromptFromTheSameAgentIsNew() {
  let first = HandsOff.needs(in: [row("blocked", rev: "r1")])
  let second = HandsOff.needs(in: [row("blocked", rev: "r2")])
  #expect(!second.subtracting(first).isEmpty)
}

@Test func workingAgentsDontInterruptThePet() {
  #expect(HandsOff.needs(in: [row("working"), row("idle", id: "b"), row("done", id: "c")]).isEmpty)
  #expect(HandsOff.needs(in: [row("error")]).count == 1)
}

@Test func levelComesFromUseAndAge() {
  var pet = PetInfo(name: "Bit", total: 2, today: 0, age: 0, asleep: false)
  #expect(pet.level == 1)
  pet.grown = 12
  #expect(pet.level == 3)
}

@Test func comingBackFromADayOffIsAHappyHello() {
  let clock = Date(timeIntervalSinceReferenceDate: 1_000_000)
  let pet = PetInfo(name: "Bit", total: 0, today: 0, age: 0, asleep: false)
  let hello = PetEvent(kind: .rested, at: clock.addingTimeInterval(-3.5))
  #expect(hello.kind.isHello)
  #expect(PetEvent(kind: .rested, at: clock).hops == 3)
  #expect(PetEvent(kind: .welcome, at: clock).hops == 5)
  #expect(PetLook.pose(pet: pet, working: 0, boardDim: false, event: hello, now: clock) == .happy)
  #expect(!PetEvent(kind: .heart, at: clock).kind.isHello)
}

@Test func moodIsSimple() {
  var pet = PetInfo(name: "Bit", total: 0, today: 0, age: 0, asleep: false)
  #expect(pet.mood == "doing fine")
  pet.birthday = true
  #expect(pet.mood == "happy birthday")
  pet.asleep = true
  #expect(pet.mood == "asleep")
}

@Test func progressIsHowFarThroughTheLevel() {
  var pet = PetInfo(name: "Bit", total: 0, today: 0, age: 0, asleep: false)
  pet.grown = 12  // level 3 runs from 12 to 27
  #expect(pet.level == 3)
  #expect(pet.progress(of: 15) == 0)
  pet.grown = 20
  #expect(pet.progress(of: 15) == 8)
}

@Test func theNextKeepsakeIsNamed() {
  var pet = PetInfo(name: "Bit", total: 0, today: 0, age: 0, asleep: false)
  for (grown, says) in [(0, "headset at level 3"), (12, "antenna at level 5"), (48, "crown at level 8"), (147, "wearing its crown")] {
    pet.grown = grown
    #expect(pet.nextKeepsake == says)
  }
}

// The board's rules for how Bit looks: firmware/main/pet.c.
private func pet(asleep: Bool = false) -> PetInfo {
  PetInfo(name: "Bit", total: 30, today: 2, age: 3, asleep: asleep)
}
private let clock = Date(timeIntervalSince1970: 1000)
private func look(_ p: PetInfo, working: Int = 0, dim: Bool = false, event: PetEvent? = nil) -> BitPose {
  PetLook.pose(pet: p, working: working, boardDim: dim, event: event, now: clock)
}

@Test func anAgentAtWorkPutsBitAtItsLaptop() {
  #expect(look(pet()) == .idle)
  #expect(look(pet(), working: 1) == .work)
}

@Test func workWakesItEvenAtNight() {
  #expect(look(pet(asleep: true)) == .nap)
  #expect(look(pet(asleep: true), working: 2) == .work)
}

@Test func aDimBoardMakesItDozeUnlessThereIsWork() {
  #expect(look(pet(), dim: true) == .nap)
  #expect(look(pet(), working: 1, dim: true) == .work)
}

@Test func aPatShowsOverEverythingThenEnds() {
  let patted = PetEvent(kind: .heart, at: clock.addingTimeInterval(-0.3))
  #expect(look(pet(), working: 1, event: patted) == .happy)
  let later = PetEvent(kind: .heart, at: clock.addingTimeInterval(-0.9))
  #expect(look(pet(), working: 1, event: later) == .work)
}

@Test func aRewardHopsOncePerTurnUpToFive() {
  #expect(PetEvent(kind: .reward, at: clock, turns: 2).hops == 2)
  #expect(PetEvent(kind: .reward, at: clock, turns: 9).hops == 5)
  let up = PetEvent(kind: .reward, at: clock.addingTimeInterval(-3.5), turns: 1, levelUp: true)
  #expect(look(pet(), event: up) == .happy)
}

@Test func helpersAreOtherAgentsAtWork() {
  #expect(PetLook.helpers(pet: pet(), working: 0, boardDim: false) == 0)
  #expect(PetLook.helpers(pet: pet(), working: 1, boardDim: false) == 0)
  #expect(PetLook.helpers(pet: pet(), working: 3, boardDim: false) == 2)
  #expect(PetLook.helpers(pet: pet(), working: 20, boardDim: false) == 6)
}

@Test func theCaptionMatchesTheBoard() {
  #expect(PetLook.caption(pet: pet(), working: 1, done: 0) == "1 agent working")
  #expect(PetLook.caption(pet: pet(), working: 2, done: 1) == "1 done \u{B7} 2 working")
  #expect(PetLook.caption(pet: pet(), working: 0, done: 0) == "2 turns today")
}
