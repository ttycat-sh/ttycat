// The panel under the menu bar icon, laid out like the board's screens.
import AppKit
import ServiceManagement
import SwiftUI

let panelWidth: CGFloat = 320
private let panelChrome: CGFloat = 44  // the tabs and padding, which stay put while a page scrolls

// @State is a macro in current SDKs, and its plugin comes only with Xcode. This builds without.
final class Local<Value>: ObservableObject {
  @Published var value: Value
  init(_ value: Value) { self.value = value }
}

struct PanelView: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    VStack(spacing: 6) {
      TopBar()
      PageScroll(tallest: m.maxPanelHeight - panelChrome) {
        VStack(spacing: 6) {
          switch m.page {
          case .agents: AgentsPage()
          case .pet: PetPage()
          case .setup: SetupPage()
          case .extra(let id): Extensions.pages.first { $0.id == id }?.view()
          }
          if let toast = m.toast {
            Text(toast).font(Pixel.body).foregroundStyle(Palette.orange).lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(8)
    .frame(width: panelWidth)
    .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
    .onPreferenceChange(PanelHeightKey.self) { m.panelHeight = $0 }
    .frame(maxHeight: .infinity, alignment: .top)  // while the window catches up, the top stays put
    .background(Palette.black)
    .environment(\.colorScheme, .dark)
  }
}

private struct PanelHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PageHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A page as tall as it needs, until it would run off the screen: then it scrolls, under the tabs.
private struct PageScroll<Content: View>: View {
  @StateObject private var height = Local<CGFloat>(0)
  let tallest: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView(.vertical, showsIndicators: height.value > tallest) {
      content.background(GeometryReader { Color.clear.preference(key: PageHeightKey.self, value: $0.size.height) })
    }
    .frame(height: min(height.value, tallest))
    .onPreferenceChange(PageHeightKey.self) { height.value = $0 }
  }
}

// The board's tab bar and its "MAC" link marker, here the other way round.
private struct TopBar: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    HStack(spacing: 2) {
      tab("Agents", count: m.rows.count, page: .agents)
      tab("Pet", count: nil, page: .pet)
      ForEach(Extensions.pages, id: \.id) { extra in
        tab(extra.title, count: nil, page: .extra(extra.id))
      }
      tab("Setup", count: nil, page: .setup, marked: m.firmwarePlan.wantsAttention)
      Spacer(minLength: 8)
      if m.boardMatters {
        Rectangle().fill(m.boardConnected ? Palette.green : Palette.faint).frame(width: 6, height: 6)
        if Extensions.pages.isEmpty {  // with more tabs, the light says it alone
          Text("BOARD").font(Pixel.small).foregroundStyle(m.boardConnected ? Palette.muted : Palette.faint)
        }
      }
    }
  }

  private func tab(_ title: String, count: Int?, page: Page, marked: Bool = false) -> some View {
    Button {
      m.page = page
      m.selected = nil
    } label: {
      VStack(spacing: 3) {
        HStack(spacing: 5) {
          Caps(title, color: m.page == page ? Palette.white : Palette.muted2)
          if let count {
            Text("\(count)").font(Pixel.small).foregroundStyle(Palette.muted)
          }
          if marked { Rectangle().fill(Palette.orange).frame(width: 6, height: 6) }
        }
        .fixedSize()  // a name is never cut short to make room
        .frame(height: 16)
        Rectangle().fill(m.page == page ? Palette.orange : Color.clear).frame(height: 2)
      }
      .padding(.horizontal, Extensions.pages.isEmpty ? 6 : 2)
    }
    .buttonStyle(PixelPress())
  }
}

// ---------------------------------------------------------------- agents

private struct AgentsPage: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    if let row = m.selectedRow {
      AgentPage(row: row)
    } else {
      list
    }
  }

  @ViewBuilder private var list: some View {
    let all = m.rows
    let ask = m.heroAsk
    // A row in the sorted list that isn't blocked is never above one that is.
    let top = all.first
    // As on the board, what needs you is the hero. When nothing does, every agent gets a row.
    let below = ask != nil
      ? all.filter { $0.id != ask?.id }
      : top.map { $0.s == "error" || $0.s == "done" } == true ? Array(all.dropFirst()) : all
    let shown = ask == nil ? 6 : 3
    if !m.welcomed { WelcomeCard() }
    if let ask {
      let asks = m.asks
      AskCard(row: ask, position: (at: (asks.firstIndex { $0.id == ask.id } ?? 0) + 1, of: asks.count)).id(ask.rev)
    } else {
      Hero(top: top)
    }
    if !below.isEmpty {
      ScrollView(.vertical, showsIndicators: below.count > shown) {
        VStack(spacing: 3) {
          ForEach(Array(below.enumerated()), id: \.element.id) { index, row in
            AgentRowView(row: row, seed: index)
          }
        }
      }
      .frame(height: CGFloat(min(below.count, shown)) * 40 - 3)
    }
    if let pet = m.status?.pet, ask == nil { PetStrip(pet: pet) }
  }
}

/// The first time: what it does by itself, and the two things it needs your click for.
private struct WelcomeCard: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Caps("Welcome", color: Palette.white)
      Text("Agents running in any terminal show up here by themselves. Two things need your OK:")
        .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      Toggled(
        title: "Answer Claude's prompts here", on: m.hookInstalled == true,
        detail: "adds one hook to Claude's settings", enabled: m.hookInstalled != nil && !m.hookBusy
      ) { m.setHook(m.hookInstalled != true) }
      Toggled(
        title: "Tell me when an agent needs me", on: m.notifyPermission == .authorized,
        detail: m.notifyPermission == .denied ? "turned off in System Settings" : "macOS will ask",
        enabled: m.notifyPermission == .notDetermined
      ) { m.turnOnNotifications() }
      PixelButton(title: "Done", loud: true, action: m.finishWelcome)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: Palette.orange)
  }
}

private struct Hero: View {
  @EnvironmentObject var m: TTYCatModel
  let top: AgentRow?

  private struct Look {
    var pose: BitPose
    var label: String
    var word: String
    var suffix = ""
    var detail: String
    var tone: Color = Palette.white
    var border: Color = Palette.line
    var dimmed = false
    var badge: [UInt8]?
    var opens = false
  }

  private var look: Look {
    guard m.status != nil else {
      return Look(
        pose: .nap, label: "Daemon", word: "STOPPED",
        detail: m.problem ?? "starting it...", tone: Palette.orange, border: Palette.orange, dimmed: true)
    }
    if let top, top.s == "error" {
      let name = "\(top.n ?? "Agent") \u{B7} \(top.p ?? "")"
      return Look(
        pose: .alert, label: name, word: "ERROR", suffix: "\(ageText(top.age)) ago",
        detail: top.d ?? "", tone: Palette.orange, border: Palette.orange, badge: PixelIcon.cross, opens: top.canOpen)
    }
    if m.flashBusy {
      return Look(
        pose: .work, label: "Board", word: "UPDATING", detail: "don't unplug it; agents keep running",
        tone: Palette.orange)
    }
    if !m.boardConnected && m.boardEverSeen {
      return Look(
        pose: .nap, label: "Board", word: "UNPLUGGED", detail: "plug it in over USB; agents still show here",
        tone: Palette.muted, dimmed: true)
    }
    if let top, top.s == "done" {
      let name = "\(top.n ?? "Agent") \u{B7} \(top.p ?? "")"
      return Look(
        pose: .happy, label: name, word: "DONE", detail: top.d ?? "", tone: Palette.green, border: Palette.green,
        opens: true)
    }
    let working = m.working
    return Look(
      pose: working > 0 ? .work : .idle, label: "Nothing needs you", word: "CLEAR",
      detail: m.rows.isEmpty ? "start an agent in any terminal" : "\(working) working \u{B7} \(m.rows.count - working) idle")
  }

  var body: some View {
    let look = self.look
    Button {
      if look.opens, let top { m.select(top) }
    } label: {
      HStack(spacing: 8) {
        ZStack(alignment: .topTrailing) {
          Rectangle().fill(Palette.black).frame(width: 56, height: 52)
          BitView(pose: look.pose, dot: 3, dimmed: look.dimmed)
            .frame(width: 56, height: 52)
          if let badge = look.badge {
            PixelIcon(rows: badge, scale: 2, color: Palette.orange).padding(2)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Caps(look.label, color: Palette.muted2)
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(look.word).font(Pixel.hero).foregroundStyle(look.tone).lineLimit(1)
            Text(look.suffix).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
          }
          Text(look.detail).font(Pixel.body).foregroundStyle(Palette.muted).lineLimit(1)
        }
        Spacer(minLength: 0)
        if look.opens { PixelIcon(rows: PixelIcon.right, scale: 1) }
      }
      .padding(8)
      .frame(maxWidth: .infinity)
      .pixelBox(Palette.card, border: look.border)
    }
    .buttonStyle(PixelPress())
    .disabled(!look.opens)
    .help(look.detail)
  }
}

private struct AgentRowView: View {
  @EnvironmentObject var m: TTYCatModel
  @StateObject private var hovering = Local(false)
  let row: AgentRow
  let seed: Int

  var body: some View {
    Button {
      m.select(row)
    } label: {
      HStack(spacing: 7) {
        stateIcon.frame(width: 16, height: 16)
        VStack(alignment: .leading, spacing: 0) {
          Text(row.p ?? "").font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
          HStack(spacing: 5) {
            if let host = row.host { Text(host).font(Pixel.small).foregroundStyle(Palette.white) }
            Text(row.d ?? "").font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 2) {
          Text(ageText(row.age)).font(Pixel.small).foregroundStyle(Palette.muted)
          Caps(row.a ?? "", color: Palette.muted2)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 37)
      .frame(maxWidth: .infinity)
      .pixelBox(Palette.tile, border: row.s == "blocked" || hovering.value ? Palette.orange : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!row.canOpen)
    .onHover { hovering.value = $0 && row.canOpen }
    .help(row.d ?? "")
  }

  // The board's status squares; a working agent is the mascot at its laptop.
  @ViewBuilder private var stateIcon: some View {
    switch row.s {
    case "blocked": square(PixelIcon.bang, fill: Palette.orange, border: Palette.orange, ink: Palette.black)
    case "error": square(PixelIcon.cross, fill: Palette.black, border: Palette.orange, ink: Palette.orange)
    case "done": square(PixelIcon.check, fill: Palette.green, border: Palette.green, ink: Palette.black)
    case "working": BitView(pose: .work, dot: 1, seed: seed)
    default: square(PixelIcon.dash, fill: Palette.tile, border: Palette.line, ink: Palette.faint)
    }
  }

  private func square(_ icon: [UInt8], fill: Color, border: Color, ink: Color) -> some View {
    ZStack {
      SteppedRect().fill(border)
      Rectangle().fill(fill).padding(2)
      PixelIcon(rows: icon, scale: 2, color: ink)
    }
  }
}

// The board's Detail screen: what this agent has been doing, and its way to the terminal.
private struct AgentPage: View {
  @EnvironmentObject var m: TTYCatModel
  let row: AgentRow

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Button {
          m.selected = nil
        } label: {
          HStack(spacing: 5) {
            PixelIcon(rows: PixelIcon.left, scale: 1)
            Caps("Back", color: Palette.white)
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(PixelPress())
        Spacer(minLength: 4)
        Text("\(stateWord) \(ageText(row.age))").font(Pixel.small).foregroundStyle(stateColor)
      }
      if row.s == "blocked" {
        AskCard(row: row).id(row.rev)
      } else {
        title
      }
      recent
      PixelButton(title: "Open in terminal") { m.open(row) }
    }
  }

  private var stateWord: String {
    switch row.s {
    case "blocked": "needs you"
    case "error": "error"
    case "done": "done"
    case "working": "working"
    default: "idle"
    }
  }

  private var stateColor: Color {
    switch row.s {
    case "blocked", "error": Palette.orange
    case "done": Palette.green
    default: Palette.muted
    }
  }

  private var title: some View {
    HStack(spacing: 8) {
      BitView(pose: row.s == "working" ? .work : row.s == "done" ? .happy : row.s == "error" ? .alert : .idle, dot: 2)
        .frame(width: 36, height: 34)
      VStack(alignment: .leading, spacing: 2) {
        Text(row.p ?? "").font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
        HStack(spacing: 5) {
          Caps(row.n ?? "Agent", color: Palette.muted2)
          if let host = row.host { Text(host).font(Pixel.small).foregroundStyle(Palette.muted2) }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .pixelBox(Palette.card, border: Palette.line)
  }

  private var recent: some View {
    VStack(alignment: .leading, spacing: 6) {
      Caps("Recent")
      if m.activity.isEmpty {
        Text(row.d ?? "nothing yet").font(Pixel.body).foregroundStyle(Palette.faint)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        FitScroll(tallest: row.s == "blocked" ? 110 : 260) {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(m.activity.enumerated()), id: \.offset) { index, item in
              HStack(alignment: .top, spacing: 6) {
                Text(item.age).font(Pixel.small).foregroundStyle(Palette.faint).frame(width: 30, alignment: .trailing)
                Rectangle().fill(item.tone == 1 ? Palette.orange : item.tone == 2 ? Palette.green : Palette.faint)
                  .frame(width: 6, height: 6)
                  .padding(.top, 4)
                Text(item.text).font(Pixel.body).foregroundStyle(index == 0 ? Palette.white : Palette.muted)
                  .lineLimit(3)
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .help(item.text)
              }
            }
          }
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

private struct PetStrip: View {
  @EnvironmentObject var m: TTYCatModel
  let pet: PetInfo

  var body: some View {
    Button { m.page = .pet } label: { strip }
      .buttonStyle(PixelPress())
      .help("Look after \(pet.name)")
  }

  private var strip: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(pet.name).font(Pixel.title).foregroundStyle(Palette.white)
        Text("LV \(pet.level) \u{B7} \(pet.snacks) snack\(pet.snacks == 1 ? "" : "s")")
          .font(Pixel.small).foregroundStyle(Palette.muted)
      }
      Spacer(minLength: 0)
      VStack(alignment: .trailing, spacing: 3) {
        PixelMeter(label: "Food", value: pet.food, low: pet.food < 25)
        PixelMeter(label: "Fun", value: pet.fun, low: pet.fun < 25)
        PixelMeter(label: "Rest", value: pet.energy, low: pet.energy < 20)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

func ageText(_ age: Double?) -> String {
  let a = Int(age ?? 0)
  if a < 60 { return "\(a)s" }
  if a < 3600 { return "\(a / 60)m" }
  return "\(a / 3600)h"
}

// ---------------------------------------------------------------- setup

private struct SetupPage: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    VStack(spacing: 6) {
      Section(title: "On this Mac") {
        Toggled(
          title: "Start at login", on: m.loginState == .enabled,
          detail: m.loginState == .requiresApproval ? "needs your OK in System Settings" : nil
        ) {
          if m.loginState == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
          } else {
            m.setStartAtLogin(m.loginState != .enabled)
          }
        }
        Toggled(
          title: "Answer prompts on the board", on: m.hookInstalled == true,
          detail: m.hookInstalled == nil ? "can't read ~/.claude/settings.json" : "the Claude Code permission hook",
          enabled: m.hookInstalled != nil && !m.hookBusy
        ) {
          m.setHook(m.hookInstalled != true)
        }
      }

      Section(title: "Notifications") {
        if m.notifyPermission == .denied {
          Text("Turned off for this app in System Settings").font(Pixel.small).foregroundStyle(Palette.orange)
          PixelButton(title: "Open System Settings") {
            let page = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=sh.ttycat.app"
            if let url = URL(string: page) { NSWorkspace.shared.open(url) }
          }
        } else if m.notifyPermission == .notDetermined {
          PixelButton(title: "Turn on notifications", action: m.turnOnNotifications)
          if let problem = m.notifyProblem {
            Text(problem).font(Pixel.small).foregroundStyle(Palette.orange).lineLimit(3)
          }
        }
        Toggled(title: "When an agent needs you", on: m.notifyAsks, detail: "answer short ones right on it") {
          m.setNotify(asks: !m.notifyAsks)
        }
        Toggled(title: "When an agent finishes", on: m.notifyFinishes, detail: "after 30 s or more of work") {
          m.setNotify(finishes: !m.notifyFinishes)
        }
        Toggled(title: "Sound for prompts", on: m.notifySound, enabled: m.notifyAsks) {
          m.setNotify(sound: !m.notifySound)
        }
        // macOS doesn't tell an app like this one whether a Focus is on, so this is always here.
        Text("A Focus holds banners back unless ttycat is allowed in it.")
          .font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
        PixelButton(title: "Focus settings") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
          }
        }
      }

      ForEach(Extensions.setupSections.indices, id: \.self) { index in
        Extensions.setupSections[index]()
      }

      if m.boardMatters { FirmwareSection() }

      Section(title: "Daemon") {
        Fact(name: "Daemon", value: daemonText, good: m.status != nil)
        Fact(name: "Board", value: m.boardMatters ? boardText : "none, and that's fine", good: m.boardConnected)
        if let problem = m.problem {
          Text(problem).font(Pixel.small).foregroundStyle(Palette.orange).lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack(spacing: 6) {
          PixelButton(title: "Restart", enabled: !m.flashBusy, action: m.restartDaemon)
          PixelButton(title: "Open log") {
            NSWorkspace.shared.open(URL(fileURLWithPath: Supervisor.logPath))
          }
        }
      }

      PixelButton(title: "Quit ttycat", enabled: !m.flashBusy) { NSApp.terminate(nil) }
      Text(quitNote).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
      m.refreshHook()
      m.refreshLogin()
      m.refreshPermission()
    }
  }

  private var daemonText: String {
    guard let status = m.status else { return "not running" }
    return m.ownsDaemon ? "running, pid \(status.pid)" : "running on its own, pid \(status.pid)"
  }

  private var boardText: String {
    guard let board = m.status?.board, board.connected else { return "not connected" }
    let port = board.port.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: "cu.", with: "") } ?? ""
    return board.fw.map { "fw \($0) \u{B7} \(port)" } ?? port
  }

  private var quitNote: String {
    m.ownsDaemon ? "Quitting stops the daemon; prompts use the terminal."
      : "A daemon started elsewhere keeps running."
  }
}

private struct FirmwareSection: View {
  @EnvironmentObject var m: TTYCatModel
  @StateObject private var confirming = Local(false)  // an unknown device: asked twice
  @StateObject private var confirmingApprove = Local(false)  // so is letting a device say yes

  var body: some View {
    Section(title: "Firmware") {
      switch m.firmwarePlan {
      case .noImage:
        note("This build carries no firmware. Build it, then run app/build.sh.")
      case .daemonTooOld:
        note("Restart the daemon to update the board from here.", warn: true)
      case .notConnected:
        Fact(name: "Board", value: "not connected", good: false)
      case .identifying:
        Fact(name: "Board", value: "connecting", good: false)
      case .unknownDevice(let port):
        Fact(name: "Board", value: "not answering", good: false)
        note("\((port as NSString).lastPathComponent) isn't answering. If that's the board, reinstalling fixes it. If it's another device, this would overwrite it.", warn: true)
        if confirming.value {
          HStack(spacing: 6) {
            PixelButton(title: "Cancel") { confirming.value = false }
            PixelButton(title: "Overwrite it", loud: true) {
              confirming.value = false
              m.updateFirmware(unknown: true, port: port)
            }
          }
        } else {
          PixelButton(title: "Reinstall firmware") { confirming.value = true }
        }
      case .customFirmware(let name, let port, let canReplace, let outdated):
        Fact(name: "Board", value: "\(name), custom firmware", good: !outdated)
        if outdated {
          note("This firmware doesn't match this version of ttycat, so nothing is being sent to it. Rebuild it from the latest source.", warn: true)
        } else {
          note("This isn't ttycat's firmware, so it won't be updated from here.")
          approveChoice(name)
        }
        if canReplace {
          if confirming.value {
            note("This erases \(name) from \(port).", warn: true)
            HStack(spacing: 6) {
              PixelButton(title: "Cancel") { confirming.value = false }
              PixelButton(title: "Erase it", loud: true, enabled: !m.flashBusy) {
                confirming.value = false
                m.updateFirmware(unknown: true)
              }
            }
          } else {
            PixelButton(title: "Replace with ttycat firmware") { confirming.value = true }
          }
        }
      case .upToDate(let version):
        Fact(name: "Board", value: "\(version), up to date", good: true)
      case .boardNewer(let board, let app):
        Fact(name: "Board", value: "\(board), newer than the app's \(app)", good: true)
      case .update(let from, let to):
        Fact(name: "Board", value: "\(from), \(to) available", good: false)
        PixelButton(title: "Update board to \(to)", loud: true, enabled: !m.flashBusy) { m.updateFirmware() }
        note("Takes about 10 seconds. Agents keep running; answer prompts here or in the terminal until it's back.")
      case .noTool(let to):
        Fact(name: "Board", value: "\(to) available", good: false)
        note("Updating needs esptool, which comes with ESP-IDF.", warn: true)
      case .writing(let pct, let to):
        Fact(name: "Writing \(to)", value: "\(pct)%", good: true)
        FlashBar(pct: pct)
        note("Don't unplug the board.")
      case .restarting(let to):
        Fact(name: "Written \(to)", value: "waiting for the board", good: true)
        FlashBar(pct: 100)
      }
      if let flash = m.status?.flash, flash.state == "failed", !m.flashBusy {
        note("Last try failed: \(flash.msg)", warn: true)
      }
    }
  }

  /// Off unless you turn it on. Only worth turning on for a device that shows the whole prompt.
  @ViewBuilder private func approveChoice(_ name: String) -> some View {
    if m.status?.board.approves == true {
      Toggled(title: "It can approve prompts", on: true, detail: "turn off to allow Deny only") {
        m.setDeviceApproves(name, false)
      }
    } else if confirmingApprove.value {
      note("Only if it shows you the whole prompt before you say yes. Otherwise you'd be approving what nobody has read.", warn: true)
      HStack(spacing: 6) {
        PixelButton(title: "Cancel") { confirmingApprove.value = false }
        PixelButton(title: "Let it approve", loud: true) {
          confirmingApprove.value = false
          m.setDeviceApproves(name, true)
        }
      }
    } else {
      Toggled(title: "It can approve prompts", on: false, detail: "it can only Deny for now") {
        confirmingApprove.value = true
      }
    }
  }

  private func note(_ text: String, warn: Bool = false) -> some View {
    Text(text).font(Pixel.small).foregroundStyle(warn ? Palette.orange : Palette.muted).lineLimit(4)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// In blocks, like the board's meters.
struct FlashBar: View {
  let pct: Int
  private let cells = 28

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<cells, id: \.self) { i in
        Rectangle().fill(i * 100 < pct * cells ? Palette.orange : Palette.line).frame(height: 8)
      }
    }
  }
}

struct Section<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Caps(title)
      content
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

struct Toggled: View {
  let title: String
  let on: Bool
  var detail: String?
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        PixelCheckbox(on: on)
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(Pixel.body).foregroundStyle(enabled ? Palette.white : Palette.faint)
          if let detail { Text(detail).font(Pixel.small).foregroundStyle(Palette.muted) }
        }
        Spacer(minLength: 0)
      }
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
  }
}

struct Fact: View {
  let name: String
  let value: String
  let good: Bool

  var body: some View {
    HStack(spacing: 6) {
      Rectangle().fill(good ? Palette.green : Palette.faint).frame(width: 6, height: 6)
      Text(name).font(Pixel.body).foregroundStyle(Palette.white)
      Spacer(minLength: 4)
      Text(value).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
    }
  }
}
