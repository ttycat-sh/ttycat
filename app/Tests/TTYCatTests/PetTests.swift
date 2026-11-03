import Foundation
import Testing
@testable import TTYCat

/// Bugs appear mid-field and stand still (speed s gives vx = s - s), so a click can be aimed.
private func still() -> BugHunt { BugHunt { n in n / 2 } }

private func row(_ s: String, id: String = "a", rev: String? = nil) -> AgentRow {
  AgentRow(id: id, s: s, a: "CC", n: "Claude", p: "shop", rev: rev)
}

@Test func nothingHappensWhileItSaysReady() {
  var hunt = still()
  #expect(hunt.step(now: 1000) == false)
  #expect(hunt.bugs.isEmpty)
  hunt.click(x: 150, y: 130, now: 1000)
  #expect(hunt.score == 0)
}

@Test func theGameLastsTwentySeconds() {
  var hunt = still()
  #expect(hunt.step(now: BugHunt.readyMs + BugHunt.playMs - 1) == false)
  #expect(hunt.step(now: BugHunt.readyMs + BugHunt.playMs) == true)
  #expect(hunt.secondsLeft(now: BugHunt.readyMs) == 20)
  #expect(hunt.secondsLeft(now: BugHunt.readyMs + BugHunt.playMs) == 0)
}

@Test func aClickOnABugSquashesItOnce() {
  var hunt = still()
  _ = hunt.step(now: 1500)
  let bug = hunt.bugs[0]
  let at = hunt.position(of: bug, now: 1500)
  hunt.click(x: at.x + 10, y: at.y + 10, now: 1500)
  #expect(hunt.score == 1)
  #expect(hunt.bugs[0].splat)
  hunt.click(x: at.x + 10, y: at.y + 10, now: 1510)
  #expect(hunt.score == 1)
}

@Test func aClickOutOfReachIsAMiss() {
  var hunt = still()
  _ = hunt.step(now: 1500)
  let at = hunt.position(of: hunt.bugs[0], now: 1500)
  hunt.click(x: at.x + 10 + BugHunt.reach + 1, y: at.y + 10, now: 1500)
  #expect(hunt.score == 0)
}

@Test func theNearestBugIsTheOneSquashed() {
  var hunt = still()
  _ = hunt.step(now: 1500)
  _ = hunt.step(now: 2200)
  #expect(hunt.bugs.count == 2)
  let at = hunt.position(of: hunt.bugs[1], now: 2200)
  hunt.click(x: at.x + 10, y: at.y + 10, now: 2200)
  #expect(hunt.score == 1)
  #expect(hunt.bugs.filter(\.splat).count == 1)
}

@Test func aSquashedBugStaysPutThenGoes() {
  var hunt = BugHunt { n in n - 1 }  // moving as fast as it can
  _ = hunt.step(now: 1500)
  let at = hunt.position(of: hunt.bugs[0], now: 1500)
  hunt.click(x: at.x + 10, y: at.y + 10, now: 1500)
  let squashed = hunt.bugs[0]
  #expect(hunt.position(of: squashed, now: 1700).x == at.x)
  _ = hunt.step(now: 1500 + BugHunt.splatMs + 1)
  #expect(!hunt.bugs.contains { $0.splat })
}

@Test func anUnsquashedBugGetsAway() {
  var hunt = still()
  _ = hunt.step(now: 1500)
  _ = hunt.step(now: 1500 + 1801)
  #expect(!hunt.bugs.contains { $0.born == 1500 })
}

@Test func bugsStayOnTheField() {
  var hunt = BugHunt { n in n - 1 }
  _ = hunt.step(now: 1500)
  let bug = hunt.bugs[0]
  let far = hunt.position(of: bug, now: 100_000)
  #expect(far.x >= 0 && far.x <= BugHunt.width - BugHunt.size)
  #expect(far.y >= 0 && far.y <= BugHunt.height - BugHunt.size)
}

@Test func neverMoreThanFiveAtOnce() {
  var hunt = still()
  var t = 1500
  while t < 1500 + 1700 {
    _ = hunt.step(now: t)
    #expect(hunt.bugs.count <= BugHunt.slots)
    t += 50
  }
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

@Test func moodSaysWhatTheBubbleMeans() {
  var pet = PetInfo(name: "Bit", total: 0, today: 0, food: 50, fun: 50, energy: 50, snacks: 0, age: 0, sick: false, asleep: false)
  #expect(pet.mood == "doing fine")
  pet.need = "mess"
  pet.poops = 2
  #expect(pet.mood == "made 2 messes")
  pet.asleep = true
  #expect(pet.mood == "asleep")
}

// The board's rules for how Bit looks: firmware/main/pet.c.
private func pet(need: String = "", asleep: Bool = false) -> PetInfo {
  var p = PetInfo(name: "Bit", total: 30, today: 2, food: 50, fun: 50, energy: 50, snacks: 1, age: 3, sick: false, asleep: asleep)
  p.need = need
  return p
}
private let clock = Date(timeIntervalSince1970: 1000)
private func look(_ p: PetInfo, working: Int = 0, dim: Bool = false, event: PetEvent? = nil) -> BitPose {
  PetLook.pose(pet: p, working: working, boardDim: dim, event: event, now: clock)
}

@Test func anAgentAtWorkPutsBitAtItsLaptop() {
  #expect(look(pet()) == .idle)
  #expect(look(pet(), working: 1) == .work)
}

@Test func sleepBeatsWorkAndWorkBeatsANeed() {
  #expect(look(pet(asleep: true), working: 2) == .nap)
  #expect(look(pet(need: "food"), working: 1) == .work)
  #expect(look(pet(need: "food")) == .sad)
}

@Test func aDimBoardMakesItDozeUnlessThereIsWork() {
  #expect(look(pet(), dim: true) == .nap)
  #expect(look(pet(), working: 1, dim: true) == .work)
}

@Test func careShowsOverEverythingThenEnds() {
  let eating = PetEvent(kind: .eat, at: clock.addingTimeInterval(-1))
  #expect(look(pet(asleep: true), event: eating) == .eat)
  let eaten = PetEvent(kind: .eat, at: clock.addingTimeInterval(-1.5))
  #expect(look(pet(), event: eaten) == .idle)
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
  #expect(PetLook.helpers(pet: pet(asleep: true), working: 3, boardDim: false) == 3)
  #expect(PetLook.helpers(pet: pet(), working: 20, boardDim: false) == 6)
}

@Test func theCaptionMatchesTheBoard() {
  #expect(PetLook.caption(pet: pet(), working: 1, done: 0) == "1 agent working")
  #expect(PetLook.caption(pet: pet(), working: 2, done: 1) == "1 done \u{B7} 2 working")
  #expect(PetLook.caption(pet: pet(), working: 0, done: 0) == "2 turns today \u{B7} 3 days old")
}
