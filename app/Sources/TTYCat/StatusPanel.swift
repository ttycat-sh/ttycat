// The menu bar icon and the window under it. A window of its own, because SwiftUI's MenuBarExtra
// grows its window but never shrinks it: a short page ended up floating inside a tall one.
import AppKit
import Combine
import SwiftUI

/// Where the panel goes: its top stays just under the icon, whatever its height. No side effects.
enum PanelPlacement {
  static let gap: CGFloat = 1
  static let margin: CGFloat = 6
  static let shortest: CGFloat = 200

  static func tallest(button: CGRect, visible: CGRect) -> CGFloat {
    max(shortest, button.minY - gap - visible.minY - margin)
  }

  static func frame(button: CGRect, visible: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
    let fitted = min(height, tallest(button: button, visible: visible))
    let x = max(min(button.minX, visible.maxX - width - margin), visible.minX + margin)
    return CGRect(x: x, y: button.minY - gap - fitted, width: width, height: fitted)
  }
}

/// Takes the keyboard without making this the active app, like Spotlight: whatever you were
/// working in stays in front, and gets the keyboard back when this closes.
private final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let action = EditKeys.action(key: event.charactersIgnoringModifiers, flags: event.modifierFlags),
      NSApp.sendAction(action, to: nil, from: self)
    {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// Cmd-V and friends come from the Edit menu, and an app with no menu bar has none: without this,
/// the panel's text fields can be typed in but not pasted into. No side effects.
enum EditKeys {
  static func action(key: String?, flags: NSEvent.ModifierFlags) -> Selector? {
    let held = flags.intersection([.command, .shift, .option, .control])
    if held == .command {
      switch key?.lowercased() {
      case "x": return #selector(NSText.cut(_:))
      case "c": return #selector(NSText.copy(_:))
      case "v": return #selector(NSText.paste(_:))
      case "a": return #selector(NSText.selectAll(_:))
      case "z": return Selector(("undo:"))
      default: return nil
      }
    }
    return held == [.command, .shift] && key?.lowercased() == "z" ? Selector(("redo:")) : nil
  }
}

@MainActor
final class StatusPanel: NSObject {
  private(set) static var shared: StatusPanel?

  private let model: TTYCatModel
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let panel = KeyPanel(
    contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 300),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
  private var watchers: [AnyCancellable] = []
  private static let escapeKey: UInt16 = 53
  private var anchor: (button: CGRect, visible: CGRect)?  // fixed while open: the icon widens with a badge
  private var clicks: Any?
  private var keys: Any?
  private var presses: Any?
  private var switches: NSObjectProtocol?
  private var screens: NSObjectProtocol?

  var isOpen: Bool { panel.isVisible }

  init(model: TTYCatModel) {
    self.model = model
    super.init()
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.hasShadow = true
    panel.isOpaque = true
    panel.backgroundColor = NSColor(Palette.black)
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    if let button = item.button {
      button.target = self
      button.action = #selector(toggle)
      button.setAccessibilityTitle("ttycat")
    }
    model.$icon.sink { [weak self] in self?.item.button?.image = $0 }.store(in: &watchers)
    model.$panelHeight.removeDuplicates().sink { [weak self] height in
      guard let self, self.isOpen else { return }
      self.place(height: height)
    }.store(in: &watchers)
    Self.shared = self
  }

  @objc private func toggle() {
    if isOpen { close() } else { open() }
  }

  /// Built new each time: a prompt's buttons get their full delay before they work, and Setup reads
  /// its settings again, every time the panel opens.
  func open() {
    guard !isOpen else { return }
    model.panelOpening()
    anchor = buttonFrame()
    model.maxPanelHeight = anchor.map { PanelPlacement.tallest(button: $0.button, visible: $0.visible) } ?? 600
    panel.contentView = NSHostingView(rootView: PanelView().environmentObject(model))
    place(height: model.panelHeight > 0 ? model.panelHeight : 300)

    // Shown once the content has measured itself, so it doesn't open at the wrong height.
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
      guard let self, self.isOpen else { return }
      self.place(height: self.model.panelHeight)
      self.panel.alphaValue = 1
    }

    // A click anywhere else closes it. Only other apps' clicks come here.
    clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    // Every click in the panel: a prompt's buttons wait until they've stopped.
    presses = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      MainActor.assumeIsolated { self?.model.lastPanelClick = Date() }
      return event
    }
    // Esc, from here: a text field in the panel would otherwise keep it for itself.
    keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == Self.escapeKey else { return event }
      MainActor.assumeIsolated { self?.close() }
      return nil
    }
    // As does moving to another app, such as Open in terminal or Cmd-Tab.
    switches = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let mine = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
      MainActor.assumeIsolated { if !mine { self?.close() } }
    }
    screens = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
  }

  func close() {
    if let clicks { NSEvent.removeMonitor(clicks) }
    if let keys { NSEvent.removeMonitor(keys) }
    if let presses { NSEvent.removeMonitor(presses) }
    presses = nil
    model.petPageOpen(false)  // nobody's looking: the once-a-second update will do
    if let switches { NSWorkspace.shared.notificationCenter.removeObserver(switches) }
    if let screens { NotificationCenter.default.removeObserver(screens) }
    clicks = nil
    keys = nil
    switches = nil
    screens = nil
    panel.orderOut(nil)
    panel.contentView = nil
    anchor = nil
    // A click on a notification makes this the active app. With no window left, your typing would
    // go nowhere: this gives the front back to whatever you were in.
    if NSApp.isActive { NSApp.hide(nil) }
  }

  private func buttonFrame() -> (button: CGRect, visible: CGRect)? {
    guard let window = item.button?.window, let screen = window.screen ?? NSScreen.main else { return nil }
    return (window.frame, screen.visibleFrame)
  }

  private func place(height: CGFloat) {
    guard height > 0, let anchor else { return }
    let frame = PanelPlacement.frame(
      button: anchor.button, visible: anchor.visible, width: panelWidth, height: height)
    panel.setFrame(frame, display: true, animate: false)
  }
}
