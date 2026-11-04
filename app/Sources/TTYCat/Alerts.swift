// Notifications: a prompt or a finished turn, unless you're already looking at that agent.
// They stay in step with the agents: once a prompt is settled anywhere, its notification goes.
import AppKit
import UserNotifications

enum AlertStep: Equatable {
  case ask(String)
  case finished(String)
  case clear(String)
}

/// Decides what to post from each new list of agents. Knows nothing about the system's
/// notifications, so all of this can be tested.
struct AlertPlanner {
  static let askGrace: TimeInterval = 3    // one answered this fast didn't need a banner
  static let finishGrace: TimeInterval = 2 // agents pause briefly between steps
  static let shortestWork: TimeInterval = 30

  private struct Track {
    var s: String
    var rev: String?
    var ask: String?
    var since: Date
    var posted = false
    var workStart: Date?
    var owes = false  // finished a long stretch of work; not reported yet
  }

  private var tracks: [String: Track] = [:]

  private static func settled(_ s: String) -> Bool { s == "done" || s == "idle" }

  /// Post it again: its notification was used up without answering the prompt.
  mutating func forget(_ id: String) { tracks[id]?.posted = false }

  mutating func plan(
    _ rows: [AgentRow], now: Date, watching: (AgentRow) -> Bool, asks: Bool, finishes: Bool
  ) -> [AlertStep] {
    var steps: [AlertStep] = []
    var alive = Set<String>()
    for row in rows where row.canOpen {
      alive.insert(row.id)
      // One already finished when this first sees it has no work to report.
      var t = tracks[row.id] ?? Track(s: row.s, rev: row.rev, ask: row.ask, since: now)
      // Text on a terminal prompt's screen can change while it's the same prompt.
      let newPrompt = row.s == "blocked" && t.s == "blocked"
        && (t.ask != row.ask || (row.ask != "terminal" && t.rev != row.rev))
      if t.s != row.s || newPrompt {
        if t.posted {
          // A new prompt takes the old one's place; anything else takes the notification away.
          if !newPrompt { steps.append(.clear(row.id)) }
          t.posted = false
        }
        if Self.settled(row.s) {
          if t.s == "working", let start = t.workStart, now.timeIntervalSince(start) >= Self.shortestWork {
            t.owes = true
          }
          if !t.owes { t.workStart = nil }
        } else {
          t.owes = false
        }
        t.s = row.s
        t.since = now
      }
      t.rev = row.rev
      t.ask = row.ask
      if row.s == "working" && t.workStart == nil {
        t.workStart = now.addingTimeInterval(-(row.age ?? 0))
      }
      if row.s == "blocked", !t.posted, asks, now.timeIntervalSince(t.since) >= Self.askGrace, !watching(row) {
        t.posted = true
        steps.append(.ask(row.id))
      }
      if t.owes, now.timeIntervalSince(t.since) >= Self.finishGrace {
        t.owes = false
        t.workStart = nil
        if finishes, !watching(row) {
          t.posted = true
          steps.append(.finished(row.id))
        }
      }
      tracks[row.id] = t
    }
    for (id, t) in tracks where !alive.contains(id) {
      if t.posted { steps.append(.clear(id)) }
      tracks[id] = nil
    }
    return steps
  }
}

/// What a click on a notification means.
enum AlertReply: Equatable {
  case deny
  case choose(Int)
  case type(String)
  case open
  case show
  case nothing

  static func from(action: String, typed: String?, answerable: Bool) -> AlertReply {
    switch action {
    case UNNotificationDefaultActionIdentifier: return answerable ? .show : .open
    case "deny": return .deny
    case "open": return .open
    case "type":
      let text = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? .nothing : .type(text)
    default:
      if action.hasPrefix("opt-"), let number = Int(action.dropFirst(4)) { return .choose(number) }
      return .nothing
    }
  }
}

extension AgentRow {
  /// One question with one answer fits on buttons. Several, or pick-any, need the panel.
  var singleChoice: Question? {
    guard ask == "choice", let qs, qs.count == 1, !qs[0].m else { return nil }
    return qs[0]
  }

  var answerable: Bool { ask == "approve" || ask == "choice" }

  var alertTitle: String {
    ([n ?? "Agent", p ?? ""] + (host.map { [$0] } ?? [])).filter { !$0.isEmpty }.joined(separator: " \u{B7} ")
  }

  var alertBody: String {
    if let qs, let first = qs.first {
      return qs.count > 1 ? "\(first.q) (+\(qs.count - 1) more)" : first.q
    }
    return body?.isEmpty == false ? body! : d ?? ""
  }
}

final class Alerts: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private static let placeholder = "An agent needs you"
  private let center = UNUserNotificationCenter.current()
  private var questions: [String: UNNotificationCategory] = [:]  // agent -> its open question
  weak var model: TTYCatModel?

  /// Before launch finishes: a click on a notification can be what starts the app.
  func start(model: TTYCatModel) {
    self.model = model
    center.delegate = self
    center.setNotificationCategories(Self.fixed)
    center.removeAllDeliveredNotifications()  // what they were about may be long settled
  }

  func stop() { center.removeAllDeliveredNotifications() }

  func refreshPermission(_ done: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
    center.getNotificationSettings { done($0.authorizationStatus) }
  }

  func requestPermission(_ done: @escaping @Sendable (UNAuthorizationStatus, String?) -> Void) {
    center.requestAuthorization(options: [.alert, .sound]) { [center] _, error in
      let problem = error?.localizedDescription
      if let problem { NSLog("notification permission: \(problem)") }
      center.getNotificationSettings { done($0.authorizationStatus, problem) }
    }
  }

  // ---------------------------------------------------------------- categories

  private static func action(_ id: String, _ title: String, _ more: UNNotificationActionOptions = []) -> UNNotificationAction {
    // Nothing is answered from a locked screen.
    UNNotificationAction(identifier: id, title: title, options: more.union(.authenticationRequired))
  }

  private static func category(_ id: String, _ actions: [UNNotificationAction]) -> UNNotificationCategory {
    UNNotificationCategory(
      identifier: id, actions: actions, intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: placeholder, options: [])
  }

  private static let fixed: Set<UNNotificationCategory> = [
    // Never Allow: that's for the panel or the board, where all of it can be read.
    category("read-first", [action("deny", "Deny", .destructive)]),
    category("terminal", [action("open", "Open terminal")]),
    category("panel", []),
  ]

  /// Options come from the agent, so each question gets its own category.
  private static func category(for question: Question, agent: String) -> UNNotificationCategory {
    var actions: [UNNotificationAction] = question.o.prefix(4).enumerated().map { action("opt-\($0)", $1.l) }
    actions.append(
      UNTextInputNotificationAction(
        identifier: "type", title: "Type an answer", options: .authenticationRequired,
        textInputButtonTitle: "Send", textInputPlaceholder: "Your answer"))
    return category("q-\(agent)", actions)
  }

  private func register() { center.setNotificationCategories(Self.fixed.union(questions.values)) }

  // ---------------------------------------------------------------- posting

  private static func askId(_ agent: String) -> String { "ask-\(agent)" }
  private static func doneId(_ agent: String) -> String { "done-\(agent)" }

  func postAsk(_ row: AgentRow, sound: Bool) {
    let content = UNMutableNotificationContent()
    content.title = row.alertTitle
    content.subtitle = row.verb ?? "needs you"
    content.body = row.alertBody
    content.threadIdentifier = row.id
    content.userInfo = ["id": row.id, "rev": row.rev ?? "", "answerable": row.answerable]
    if sound { content.sound = .default }

    var category = "panel"
    if row.ask == "approve" {
      category = "read-first"
      content.subtitle += " \u{B7} click to answer"
    } else if row.ask != "choice" {
      category = "terminal"
    }
    let request = { [center] (content: UNNotificationContent) in
      center.add(UNNotificationRequest(identifier: Self.askId(row.id), content: content, trigger: nil)) { error in
        if let error { NSLog("notification: \(error.localizedDescription)") }
      }
    }
    if let question = row.singleChoice {
      let made = Self.category(for: question, agent: row.id)
      questions[row.id] = made
      register()
      content.categoryIdentifier = made.identifier
      let finished = content.copy() as! UNNotificationContent
      // Registering is asynchronous, and buttons are looked up when it's shown.
      center.getNotificationCategories { _ in request(finished) }
    } else {
      content.categoryIdentifier = category
      request(content)
    }
  }

  func postFinished(_ row: AgentRow) {
    let content = UNMutableNotificationContent()
    content.title = row.alertTitle
    content.subtitle = "finished"
    content.body = row.said?.isEmpty == false ? row.said! : ""
    content.threadIdentifier = row.id
    content.categoryIdentifier = "terminal"
    content.userInfo = ["id": row.id, "rev": "", "answerable": false]
    center.add(UNNotificationRequest(identifier: Self.doneId(row.id), content: content, trigger: nil))
  }

  /// Something you asked for from a notification didn't work, and there's no panel open to say so.
  func postNote(_ message: String) {
    let content = UNMutableNotificationContent()
    content.title = "ttycat"
    content.body = message
    content.categoryIdentifier = "panel"
    center.add(UNNotificationRequest(identifier: "note", content: content, trigger: nil))
  }

  func clear(_ agent: String) {
    center.removeDeliveredNotifications(withIdentifiers: [Self.askId(agent), Self.doneId(agent)])
    if questions.removeValue(forKey: agent) != nil { register() }
  }

  // ---------------------------------------------------------------- the panel

  @MainActor static var panelIsOpen: Bool { StatusPanel.shared?.isOpen == true }

  @MainActor static func openPanel() { StatusPanel.shared?.open() }

  // ---------------------------------------------------------------- the system calling back

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler done: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    done(notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler done: @escaping @Sendable () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let id = info["id"] as? String ?? ""
    let rev = info["rev"] as? String ?? ""
    let reply = AlertReply.from(
      action: response.actionIdentifier, typed: (response as? UNTextInputNotificationResponse)?.userText,
      answerable: info["answerable"] as? Bool ?? false)
    let delivered = response.notification.date
    DispatchQueue.main.async {
      MainActor.assumeIsolated { self.model?.alertReply(reply, id: id, rev: rev, delivered: delivered) }
      done()
    }
  }
}
