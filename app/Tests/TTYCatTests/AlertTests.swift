import Foundation
import Testing
import UserNotifications
@testable import TTYCat

private let start = Date(timeIntervalSince1970: 1_000_000)

private func row(_ s: String, id: String = "a", rev: String? = nil, ask: String? = nil, body: String? = nil, age: Double = 0) -> AgentRow {
  AgentRow(id: id, s: s, a: "CC", n: "Claude", p: "shop", age: age, body: body, rev: rev, ask: ask)
}

/// A planner fed one list per moment; returns what each moment decided.
private struct Run {
  var planner = AlertPlanner()
  var watching = false
  var asks = true
  var finishes = true

  mutating func at(_ seconds: Double, _ rows: AgentRow...) -> [AlertStep] {
    let watching = self.watching
    return planner.plan(rows, now: start.addingTimeInterval(seconds), watching: { _ in watching }, asks: asks, finishes: finishes)
  }
}

@Suite struct Prompts {
  @Test func postsOnceAfterTheGrace() {
    var run = Run()
    #expect(run.at(0, row("working")) == [])
    #expect(run.at(1, row("blocked", rev: "r1", ask: "approve")) == [])
    #expect(run.at(3, row("blocked", rev: "r1", ask: "approve")) == [])
    #expect(run.at(4, row("blocked", rev: "r1", ask: "approve")) == [.ask("a")])
    #expect(run.at(5, row("blocked", rev: "r1", ask: "approve")) == [])
  }

  @Test func answeredQuicklyNeverPosts() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(2, row("working")) == [])
    #expect(run.at(9, row("working")) == [])
  }

  @Test func settledTakesTheNotificationAway() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(3, row("blocked", rev: "r1", ask: "approve")) == [.ask("a")])
    #expect(run.at(4, row("working")) == [.clear("a")])
  }

  @Test func aNewPromptReplacesTheOld() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(3, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(4, row("blocked", rev: "r2", ask: "approve")) == [])  // no clear: it's replaced
    #expect(run.at(7, row("blocked", rev: "r2", ask: "approve")) == [.ask("a")])
  }

  @Test func aTerminalPromptsChangingScreenIsTheSamePrompt() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "terminal"))
    #expect(run.at(3, row("blocked", rev: "r1", ask: "terminal")) == [.ask("a")])
    #expect(run.at(4, row("blocked", rev: "r2", ask: "terminal")) == [])
    #expect(run.at(9, row("blocked", rev: "r3", ask: "terminal")) == [])
  }

  @Test func oneNoLongerAnswerableHereIsPostedAgain() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(3, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(4, row("blocked", rev: "r2", ask: "terminal"))
    #expect(run.at(7, row("blocked", rev: "r2", ask: "terminal")) == [.ask("a")])
  }

  @Test func waitsWhileYouAreLookingThenPostsWhenYouLeave() {
    var run = Run()
    run.watching = true
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(10, row("blocked", rev: "r1", ask: "approve")) == [])
    run.watching = false
    #expect(run.at(11, row("blocked", rev: "r1", ask: "approve")) == [.ask("a")])
  }

  @Test func oneAlreadyWaitingAtLaunchIsPosted() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve", age: 100))
    #expect(run.at(3, row("blocked", rev: "r1", ask: "approve", age: 103)) == [.ask("a")])
  }

  @Test func forgottenIsPostedAgain() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(3, row("blocked", rev: "r1", ask: "approve"))
    run.planner.forget("a")
    #expect(run.at(4, row("blocked", rev: "r1", ask: "approve")) == [.ask("a")])
  }

  @Test func turnedOffPostsNothing() {
    var run = Run()
    run.asks = false
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(5, row("blocked", rev: "r1", ask: "approve")) == [])
  }
}

@Suite struct Finishing {
  @Test func longWorkIsReported() {
    var run = Run()
    _ = run.at(0, row("working"))
    #expect(run.at(40, row("done")) == [])
    #expect(run.at(42, row("done")) == [.finished("a")])
    #expect(run.at(43, row("done")) == [])
  }

  @Test func shortWorkIsNot() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(10, row("done"))
    #expect(run.at(30, row("done")) == [])
  }

  @Test func alreadyDoneAtLaunchIsNot() {
    var run = Run()
    _ = run.at(0, row("done", age: 500))
    #expect(run.at(30, row("done", age: 530)) == [])
  }

  @Test func alreadyWorkingAtLaunchCountsItsAge() {
    var run = Run()
    _ = run.at(0, row("working", age: 100))
    _ = run.at(1, row("done"))
    #expect(run.at(3, row("done")) == [.finished("a")])
  }

  @Test func aPauseBetweenStepsIsNot() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(40, row("done"))
    #expect(run.at(41, row("working")) == [])
    #expect(run.at(50, row("working")) == [])
    _ = run.at(60, row("done"))
    #expect(run.at(62, row("done")) == [.finished("a")])  // and the time before the pause still counts
  }

  @Test func herdrGoingStraightToIdleCounts() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(40, row("idle"))
    #expect(run.at(42, row("idle")) == [.finished("a")])
  }

  @Test func doneTurningIdleInTheGraceStillCounts() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(40, row("done"))
    _ = run.at(41, row("idle"))
    #expect(run.at(43, row("idle")) == [.finished("a")])
  }

  @Test func timeWaitingOnAPromptIsPartOfTheWork() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(20, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(21, row("working"))  // answered at once
    _ = run.at(35, row("done"))
    #expect(run.at(37, row("done")) == [.finished("a")])
  }

  @Test func stoppedAtAPromptIsNotReportedAsFinished() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(50, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(51, row("idle"))
    #expect(run.at(60, row("idle")) == [])
  }

  @Test func seenTakesTheNotificationAway() {
    var run = Run()
    _ = run.at(0, row("working"))
    _ = run.at(40, row("done"))
    _ = run.at(42, row("done"))
    #expect(run.at(50, row("idle")) == [.clear("a")])
  }

  @Test func notWhileYouAreLookingAndNotLaterEither() {
    var run = Run()
    run.watching = true
    _ = run.at(0, row("working"))
    _ = run.at(40, row("done"))
    #expect(run.at(42, row("done")) == [])
    run.watching = false
    #expect(run.at(50, row("done")) == [])
  }
}

@Suite struct Agents {
  @Test func oneThatEndedTakesItsNotificationWithIt() {
    var run = Run()
    _ = run.at(0, row("blocked", rev: "r1", ask: "approve"))
    _ = run.at(3, row("blocked", rev: "r1", ask: "approve"))
    #expect(run.at(4) == [.clear("a")])
  }

  @Test func anUnreachableMachineIsNotAnAlert() {
    var run = Run()
    let down = AgentRow(id: "1/down", s: "error", a: "--", p: "not reachable")
    #expect(run.at(0, down) == [])
    #expect(run.at(60, down) == [])
  }

  @Test func eachAgentOnItsOwn() {
    var run = Run()
    _ = run.at(0, row("blocked", id: "a", rev: "r1", ask: "approve"), row("blocked", id: "b", rev: "r2", ask: "choice"))
    #expect(run.at(3, row("blocked", id: "a", rev: "r1", ask: "approve"), row("blocked", id: "b", rev: "r2", ask: "choice"))
      == [.ask("a"), .ask("b")])
  }
}

@Suite struct Buttons {
  @Test func allowOnlyWhenAllOfItShows() {
    #expect(row("blocked", ask: "approve", body: "npm test").allowsFromBanner)
    #expect(!row("blocked", ask: "approve", body: "npm test\nrm -rf /").allowsFromBanner)
    #expect(!row("blocked", ask: "approve", body: String(repeating: "x", count: 81)).allowsFromBanner)
    #expect(!row("blocked", ask: "approve", body: "").allowsFromBanner)
    #expect(!row("blocked", ask: "terminal", body: "npm test").allowsFromBanner)
  }

  @Test func onlyOneSingleAnswerQuestionFitsOnButtons() {
    let one = Question(q: "Which?", m: false, o: [])
    let many = Question(q: "Which?", m: true, o: [])
    var r = row("blocked", ask: "choice")
    r.qs = [one]
    #expect(r.singleChoice != nil)
    r.qs = [many]
    #expect(r.singleChoice == nil)
    r.qs = [one, one]
    #expect(r.singleChoice == nil)
  }

  @Test func repliesMeanWhatTheySay() {
    let from = AlertReply.from
    #expect(from("allow", nil, true) == .allowOrDeny("allow"))
    #expect(from("deny", nil, true) == .allowOrDeny("deny"))
    #expect(from("opt-2", nil, true) == .choose(2))
    #expect(from("type", " hi ", true) == .type("hi"))
    #expect(from("type", "   ", true) == .nothing)
    #expect(from("opt-x", nil, true) == .nothing)
    #expect(from("open", nil, false) == .open)
    #expect(from(UNNotificationDefaultActionIdentifier, nil, true) == .show)
    #expect(from(UNNotificationDefaultActionIdentifier, nil, false) == .open)
    #expect(from(UNNotificationDismissActionIdentifier, nil, true) == .nothing)
  }
}
