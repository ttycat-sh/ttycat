// Looking after Bit from the panel: the board's home screen and bug hunt.
//
// The pet's life is all in the daemon (daemon/petstate.py), so the board and this page are two
// views of the same pet. It never makes a sound and never sends a notification: those mean an
// agent needs you.
import SwiftUI

/// The bug hunt's rules, from firmware/main/game.c, with no drawing: all of this can be tested.
struct BugHunt {
  static let readyMs = 1500
  static let playMs = 20000
  static let slots = 5
  static let size = 20
  static let reach = 20    // from the bug's centre; a pointer is more exact than the board's finger
  static let splatMs = 280
  static let width = 304
  static let height = 272

  struct Bug {
    var x0: Int, y0: Int, vx: Int, vy: Int
    var born: Int, dies: Int
    var splat = false
    var splatAt = 0
  }

  private(set) var bugs: [Bug] = []
  private(set) var score = 0
  private var nextSpawn = BugHunt.readyMs
  private let random: (Int) -> Int

  /// `random(n)` gives a number from 0 up to n, not including n.
  init(random: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) { self.random = random }

  func secondsLeft(now: Int) -> Int { max(0, Self.readyMs + Self.playMs - now + 999) / 1000 }

  func position(of bug: Bug, now: Int) -> (x: Int, y: Int) {
    let x = bug.x0 + bug.vx * (now - bug.born) / 1000
    let y = bug.y0 + bug.vy * (now - bug.born) / 1000
    return (min(max(x, 0), Self.width - Self.size), min(max(y, 0), Self.height - Self.size))
  }

  /// True once time is up.
  mutating func step(now: Int) -> Bool {
    let played = now - Self.readyMs
    if played < 0 { return false }
    if played >= Self.playMs { return true }
    if now >= nextSpawn {
      spawn(now: now, played: played)
      nextSpawn = now + 650 - played / 50  // they come faster, and move faster, as it goes on
    }
    bugs.removeAll { $0.splat ? now - $0.splatAt > Self.splatMs : now >= $0.dies }
    return false
  }

  private mutating func spawn(now: Int, played: Int) {
    guard bugs.count < Self.slots else { return }
    let speed = 12 + played / 500
    bugs.append(Bug(
      x0: random(Self.width - Self.size), y0: random(Self.height - Self.size),
      vx: random(speed * 2 + 1) - speed, vy: random(speed * 2 + 1) - speed,
      born: now, dies: now + 1800 - played / 25))
  }

  /// A click on the field. The nearest bug in reach is squashed where it stands.
  mutating func click(x: Int, y: Int, now: Int) {
    guard now >= Self.readyMs else { return }
    var hit: Int?
    var best = Int.max
    for (i, bug) in bugs.enumerated() where !bug.splat {
      let at = position(of: bug, now: now)
      let dx = at.x + Self.size / 2 - x, dy = at.y + Self.size / 2 - y
      guard abs(dx) <= Self.reach, abs(dy) <= Self.reach, dx * dx + dy * dy < best else { continue }
      best = dx * dx + dy * dy
      hit = i
    }
    guard let hit else { return }
    let at = position(of: bugs[hit], now: now)
    bugs[hit].x0 = at.x
    bugs[hit].y0 = at.y
    bugs[hit].vx = 0
    bugs[hit].vy = 0
    bugs[hit].born = now
    bugs[hit].splat = true
    bugs[hit].splatAt = now
    score += 1
  }
}

/// The board's rule for when a prompt interrupts the pet: whoever was clicking at bugs is still
/// clicking, and the next thing under the pointer may be Allow. So nothing on a prompt works until
/// a moment has passed and the clicks have stopped.
enum HandsOff {
  static let afterInterruption: TimeInterval = 1.5  // HANDS_OFF_MS in firmware/main/ui.c
  static let afterClick: TimeInterval = 0.8         // HANDS_OFF_MORE_MS

  static func clear(now: Date, until: Date, lastClick: Date) -> Bool {
    now >= until && now.timeIntervalSince(lastClick) >= afterClick
  }

  /// What needs you now that didn't before. A different prompt from the same agent counts as new.
  static func needs(in rows: [AgentRow]) -> Set<String> {
    Set(rows.filter(\.needsYou).map { "\($0.id)|\($0.rev ?? "")" })
  }
}

@MainActor
final class HuntGame: ObservableObject {
  @Published private(set) var hunt = BugHunt()
  @Published private(set) var now = 0
  @Published private(set) var over = false
  @Published private(set) var doneReady = false
  let best: Int
  private var timer: Timer?
  private let started = Date()
  private let finished: (Int) -> Void
  private static let doneDelay = 900  // frantic clicks at the end don't dismiss the score

  init(best: Int, finished: @escaping (Int) -> Void) {
    self.best = best
    self.finished = finished
    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// A frozen game, to see how it looks.
  init(previewAt ms: Int, over: Bool, best: Int) {
    self.best = best
    self.finished = { _ in }
    self.over = over
    self.now = ms
    self.doneReady = over
    var seed = 7
    var sample = BugHunt { n in
      seed = (seed &* 31 &+ 11) % 9973
      return seed % n
    }
    var t = BugHunt.readyMs
    while t <= ms {
      _ = sample.step(now: t)
      if t % 1300 == 0 { sample.click(x: 150, y: 130, now: t) }
      t += 50
    }
    hunt = sample
  }

  var score: Int { hunt.score }
  var newBest: Bool { hunt.score > best }

  func click(x: Int, y: Int) {
    guard !over else { return }
    hunt.click(x: x, y: y, now: now)
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    now = Int(Date().timeIntervalSince(started) * 1000)
    if over {
      if !doneReady, now >= Self.gameLength + Self.doneDelay {
        doneReady = true
        stop()
      }
      return
    }
    if hunt.step(now: now) {
      over = true
      finished(hunt.score)
    }
  }

  private static var gameLength: Int { BugHunt.readyMs + BugHunt.playMs }
}

// ---------------------------------------------------------------- sprites

/// firmware/main/pet.c's little pictures: one string per row, "o" lit.
struct PixelMap: View {
  static let heart = [".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."]
  static let food = ["...o...", ".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo.."]
  static let poop = ["...o...", "..ooo..", ".ooooo.", ".ooooo.", "ooooooo", "ooooooo"]
  static let cross = ["..ooo..", "..ooo..", "ooooooo", "ooooooo", "..ooo..", "..ooo.."]
  static let zzz = ["ooooo..", "...o...", "..o....", ".o.....", "ooooo..", "......."]
  static let bored = [".oooo..", "o....o.", "...oo..", "..o....", ".......", "..o...."]
  static let spark = ["...o...", "..o.o..", ".o...o.", "..o.o..", "...o...", "......."]

  let rows: [String]
  var dot: CGFloat = 2
  var color: Color = Palette.white

  var body: some View {
    Canvas { ctx, _ in
      for (j, row) in rows.enumerated() {
        for (i, c) in row.enumerated() where c == "o" {
          ctx.fill(Path(CGRect(x: CGFloat(i) * dot, y: CGFloat(j) * dot, width: dot, height: dot)), with: .color(color))
        }
      }
    }
    .frame(width: CGFloat(rows.first?.count ?? 0) * dot, height: CGFloat(rows.count) * dot)
  }
}

private let brown = Color(hex: 0x8A5A2B)
private let red = Color(hex: 0xE5484D)

private enum BugSprite {
  static let a = ["..........", "..w....w..", "...w..w...", "..gggggg..", "w.gwggwg.w", ".wggggggw.", "..gggggg..", "w.gggggg.w", ".w..gg..w.", ".........."]
  static let b = ["..........", "...w..w...", "...w..w...", "w.gggggg.w", ".wgwggwgw.", "..gggggg..", "w.gggggg.w", ".wgggggg.w", "....gg....", ".........."]
  static let splat = ["o...o....o", "..o...o...", ".o.ooo..o.", "...oooo...", "o.oooooo.o", "..ooooo...", ".o.ooo.o..", "...o...o..", "o.....o...", "...o.....o"]
}

// ---------------------------------------------------------------- the game

private struct BugHuntView: View {
  @EnvironmentObject var m: TTYCatModel
  @ObservedObject var game: HuntGame

  var body: some View {
    VStack(spacing: 6) {
      if game.over { result } else { playing }
    }
  }

  private var playing: some View {
    let played = game.now - BugHunt.readyMs
    let left = Double(BugHunt.playMs - max(played, 0)) / Double(BugHunt.playMs)
    return VStack(spacing: 4) {
      HStack {
        Caps("Bugs \(game.score)", color: Palette.white)
        Spacer()
        if played >= 0 {
          Text("\(game.hunt.secondsLeft(now: game.now))s").font(Pixel.body).foregroundStyle(Palette.orange)
        }
      }
      .frame(height: 16)
      GeometryReader { space in
        ZStack(alignment: .leading) {
          Rectangle().fill(Palette.line)
          Rectangle().fill(played > BugHunt.playMs - 5000 ? Palette.white : Palette.orange)
            .frame(width: space.size.width * max(0, min(1, left)))
        }
      }
      .frame(height: 4)
      field
        .frame(width: CGFloat(BugHunt.width), height: CGFloat(BugHunt.height))
        .pixelBox(Palette.black, border: Palette.line)
    }
  }

  private var field: some View {
    let now = game.now
    return ZStack {
      Canvas { ctx, _ in
        let walking = (now / 150) % 2 == 1
        for bug in game.hunt.bugs {
          let at = game.hunt.position(of: bug, now: now)
          let rows = bug.splat ? BugSprite.splat : walking ? BugSprite.a : BugSprite.b
          for (j, row) in rows.enumerated() {
            for (i, c) in row.enumerated() where c != "." {
              let color = c == "g" ? Palette.green : c == "w" ? Palette.white : Palette.orange
              let cell = CGRect(x: CGFloat(at.x + i * 2), y: CGFloat(at.y + j * 2), width: 2, height: 2)
              ctx.fill(Path(cell), with: .color(color))
            }
          }
        }
      }
      if now < BugHunt.readyMs {
        VStack(spacing: 8) {
          Text("READY").font(Pixel.hero).foregroundStyle(Palette.orange)
          Text("click the bugs").font(Pixel.body).foregroundStyle(Palette.muted)
        }
      }
    }
    .contentShape(Rectangle())
    .overlay(PressCatcher { point in game.click(x: Int(point.x), y: Int(point.y)) })
  }

  private var result: some View {
    VStack(spacing: 6) {
      Text("\(game.score)").font(Pixel.hero).foregroundStyle(Palette.orange).padding(.top, 8)
      Text(game.score == 1 ? "bug squashed" : "bugs squashed").font(Pixel.body).foregroundStyle(Palette.white)
      Text(game.newBest ? "new best!" : "best \(game.best)").font(Pixel.body)
        .foregroundStyle(game.newBest ? Palette.green : Palette.muted)
      PixelButton(title: "Done", loud: game.doneReady, enabled: game.doneReady) { m.endHunt() }
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

/// Counts on the press, as on the board, not on release: at this pace a click is often a little drag.
private struct PressCatcher: NSViewRepresentable {
  let pressed: (CGPoint) -> Void

  final class View: NSView {
    var pressed: ((CGPoint) -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pressed?(convert(event.locationInWindow, from: nil)) }
  }

  func makeNSView(context: Context) -> View {
    let view = View()
    view.pressed = pressed
    return view
  }

  func updateNSView(_ view: View, context: Context) { view.pressed = pressed }
}

// ---------------------------------------------------------------- the page

/// Care, or finished turns: shown here and on the board alike. Timings are firmware/main/pet.c's.
struct PetEvent: Equatable {
  enum Kind: String { case eat, heart, sparkle, heal, reward }
  let kind: Kind
  let at: Date
  var turns = 0
  var levelUp = false

  static let eatFor: TimeInterval = 1.4
  static let hopFor: TimeInterval = 0.42
  static let floatFor: TimeInterval = 1.3
  static let plusFor: TimeInterval = 1.8
  static let bannerFor: TimeInterval = 4

  var hops: Int { kind == .reward ? min(max(turns, 1), 5) : 2 }
  var lasts: TimeInterval {
    switch kind {
    case .eat: return Self.eatFor
    case .reward: return levelUp ? Self.bannerFor : max(Self.plusFor, Double(hops) * Self.hopFor)
    default: return Self.floatFor
    }
  }
}

/// How Bit looks, by the board's rules (pet_draw in firmware/main/pet.c), so the two agree. Where it
/// happens to wander on the board's screen is the one thing that isn't shared.
enum PetLook {
  /// A dim screen sends it to sleep too, unless there's work on.
  static func asleep(pet: PetInfo, working: Int, boardDim: Bool) -> Bool {
    pet.asleep || (boardDim && working == 0)
  }

  static func pose(pet: PetInfo, working: Int, boardDim: Bool, event: PetEvent?, now: Date) -> BitPose {
    if let event {
      let age = now.timeIntervalSince(event.at)
      if event.kind == .eat, age < PetEvent.eatFor { return .eat }
      if event.kind != .eat, age < Double(event.hops) * PetEvent.hopFor { return .happy }
      if event.levelUp, age < PetEvent.bannerFor { return .happy }
    }
    if asleep(pet: pet, working: working, boardDim: boardDim) { return .nap }
    if working > 0 { return .work }
    return pet.need.isEmpty ? .idle : .sad
  }

  /// Small ones at laptops: one for each agent Bit isn't already working for.
  static func helpers(pet: PetInfo, working: Int, boardDim: Bool) -> Int {
    min(6, max(0, asleep(pet: pet, working: working, boardDim: boardDim) ? working : working - 1))
  }

  /// The board's line under the pet.
  static func caption(pet: PetInfo, working: Int, done: Int) -> String {
    if done > 0 { return "\(done) done \u{B7} \(working) working" }
    if working > 0 { return "\(working) agent\(working == 1 ? "" : "s") working" }
    return "\(pet.today) turn\(pet.today == 1 ? "" : "s") today \u{B7} \(pet.age) day\(pet.age == 1 ? "" : "s") old"
  }

  /// How high it is in a hop, in dots.
  static func lift(event: PetEvent?, now: Date) -> Int {
    guard let event, event.kind != .eat else { return 0 }
    let age = now.timeIntervalSince(event.at)
    guard age >= 0, age < Double(event.hops) * PetEvent.hopFor else { return 0 }
    let t = age.truncatingRemainder(dividingBy: PetEvent.hopFor) / PetEvent.hopFor
    return Int(4 * 3 * t * (1 - t))
  }
}

struct PetPage: View {
  @EnvironmentObject var m: TTYCatModel

  private var boardDim: Bool { m.status?.board.dim == true }

  var body: some View {
    Group {
      if let game = m.hunt {
        BugHuntView(game: game)
      } else if let pet = m.status?.pet {
        care(pet)
      } else {
        Text("The daemon isn't running, so Bit can't be looked after.")
          .font(Pixel.body).foregroundStyle(Palette.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .pixelBox(Palette.tile, border: Palette.line)
      }
    }
    .onAppear { m.petPageOpen(true) }
    .onDisappear { m.petPageOpen(false) }
  }

  private func care(_ pet: PetInfo) -> some View {
    VStack(spacing: 6) {
      if m.needs > 0 {
        Button { m.page = .agents } label: {
          HStack {
            Caps("\(m.needs) agent\(m.needs == 1 ? " needs" : "s need") you", color: Palette.black)
            Spacer()
            PixelIcon(rows: PixelIcon.right, scale: 2, color: Palette.black)
          }
          .padding(.horizontal, 8)
          .frame(maxWidth: .infinity, minHeight: 26)
          .pixelBox(Palette.orange)
        }
        .buttonStyle(PixelPress())
      }
      stage(pet)
      buttons(pet)
      HStack {
        Text(PetLook.caption(pet: pet, working: m.working, done: m.rows.filter { $0.s == "done" }.count))
          .font(Pixel.small).foregroundStyle(Palette.muted)
        Spacer()
        Text("best \(pet.best)").font(Pixel.small).foregroundStyle(Palette.muted)
      }
      .padding(.horizontal, 2)
    }
  }

  private func stage(_ pet: PetInfo) -> some View {
    let helpers = PetLook.helpers(pet: pet, working: m.working, boardDim: boardDim)
    return HStack(alignment: .top, spacing: 8) {
      Button {
        m.petAct("pet-pat")  // the heart comes back with the state, as it does on the board
      } label: {
        // Only for the reaction's coming and going: the sprite keeps its own time.
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
          bit(pet, now: context.date)
        }
        .frame(width: 96, height: 96)
        .pixelBox(Palette.black)
      }
      .buttonStyle(PixelPress())
      .help("Pat \(pet.name)")
      .accessibilityLabel("Pat \(pet.name)")  // not what's drifting over it

      VStack(alignment: .leading, spacing: 3) {
        Text(pet.name).font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
        Text("LV \(pet.level) \u{B7} \(pet.snacks) snack\(pet.snacks == 1 ? "" : "s")")
          .font(Pixel.small).foregroundStyle(Palette.muted)
        HStack(spacing: 4) {
          Text(mood(pet)).font(Pixel.small).foregroundStyle(pet.need.isEmpty || pet.asleep ? Palette.muted : Palette.orange)
            .lineLimit(1)
          ForEach(0..<min(pet.poops, 3), id: \.self) { _ in PixelMap(rows: PixelMap.poop, dot: 1, color: brown) }
          ForEach(0..<helpers, id: \.self) { i in BitView(pose: .work, dot: 1, seed: i + 1) }
        }
        .frame(height: 14)
        Spacer(minLength: 2)
        PixelMeter(label: "Food", value: pet.food, low: pet.food < 25)
        PixelMeter(label: "Fun", value: pet.fun, low: pet.fun < 25)
        PixelMeter(label: "Rest", value: pet.energy, low: pet.energy < 20)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(8)
    .frame(height: 112)
    .pixelBox(Palette.card, border: pet.sick ? red : Palette.line)
  }

  private func mood(_ pet: PetInfo) -> String {
    if !pet.asleep, m.working == 0, boardDim { return "dozing" }  // only as deep as the board's dim screen
    if !pet.asleep, m.working > 0, pet.need.isEmpty { return "at work" }
    return pet.mood
  }

  private func bit(_ pet: PetInfo, now: Date) -> some View {
    let event = m.petEvent.flatMap { now.timeIntervalSince($0.at) < $0.lasts ? $0 : nil }
    let pose = PetLook.pose(pet: pet, working: m.working, boardDim: boardDim, event: event, now: now)
    let age = event.map { now.timeIntervalSince($0.at) } ?? 0
    let lift = PetLook.lift(event: event, now: now)
    return ZStack(alignment: .topTrailing) {
      BitView(pose: pose, dot: 5, level: pet.level, sick: pet.sick, headroom: 3)
        .offset(y: CGFloat(-lift) * 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
      if let event, event.levelUp, age < PetEvent.bannerFor {
        Caps("Level \(pet.level)", color: Palette.green).frame(maxWidth: .infinity, alignment: .topLeading).padding(4)
      } else if pose == .nap {
        zees(now: now)
      } else if pose == .work {
        workBits(now: now)
      } else if !pet.need.isEmpty, event == nil, let wants = wantsBubble(pet) {
        wants.padding(3)
      }
      if let event { floating(event, age: age) }
    }
  }

  /// What it's eating, what it felt, or the turns it just earned.
  @ViewBuilder private func floating(_ event: PetEvent, age: TimeInterval) -> some View {
    let t = min(1, age / event.lasts)
    switch event.kind {
    case .eat:
      PixelMap(rows: PixelMap.food, dot: age < 0.47 ? 3 : age < 0.93 ? 2 : 1, color: Palette.green)
        .frame(maxWidth: .infinity, alignment: .center).offset(y: 2)
    case .heart:
      if age < PetEvent.floatFor {
        PixelMap(rows: PixelMap.heart, dot: 2, color: Palette.white)
          .frame(maxWidth: .infinity, alignment: .center).offset(y: 12 - 12 * t)
      }
    case .heal:
      if age < PetEvent.floatFor {
        PixelMap(rows: PixelMap.cross, dot: 2, color: Palette.green)
          .frame(maxWidth: .infinity, alignment: .center).offset(y: 12 - 12 * t)
      }
    case .sparkle:
      if age < PetEvent.floatFor {
        HStack(spacing: 34) {
          PixelMap(rows: PixelMap.spark, dot: 2, color: Palette.white)
          PixelMap(rows: PixelMap.spark, dot: 2, color: Palette.white).offset(y: -6)
        }
        .frame(maxWidth: .infinity, alignment: .center).offset(y: 16 - 10 * t)
      }
    case .reward:
      if age < PetEvent.plusFor {
        Text("+\(event.turns)").font(Pixel.body).foregroundStyle(Palette.green).padding(.trailing, 6)
          .offset(y: 8 - 8 * min(1, age / PetEvent.plusFor))
      }
    }
  }

  /// Drifting up, as on the board.
  private func zees(now: Date) -> some View {
    let s = now.timeIntervalSinceReferenceDate
    return ZStack(alignment: .topTrailing) {
      ForEach(0..<2, id: \.self) { i in
        let t = (s + Double(i) * 1.4).truncatingRemainder(dividingBy: 2.8) / 2.8
        Caps("Z", color: i == 0 ? Palette.orange : Palette.muted)
          .offset(x: -14 + 10 * t, y: 26 - 22 * t)
      }
    }
  }

  /// Its work drifts off, as on the board.
  private func workBits(now: Date) -> some View {
    let s = now.timeIntervalSinceReferenceDate
    let marks = ["1", "0", ";"]
    return ZStack(alignment: .topTrailing) {
      ForEach(0..<3, id: \.self) { i in
        let phase = (s + Double(i) * 0.8) / 2.4
        let t = phase.truncatingRemainder(dividingBy: 1)
        Text(marks[Int(phase) % 3]).font(Pixel.small).foregroundStyle(Palette.green)
          .offset(x: -3 - CGFloat(i) * 6, y: 24 - 20 * t)
      }
    }
  }

  private func wantsBubble(_ pet: PetInfo) -> AnyView? {
    let picture: ([String], Color)?
    switch pet.need {
    case "sick": picture = (PixelMap.cross, red)
    case "food": picture = (PixelMap.food, Palette.orange)
    case "mess": picture = (PixelMap.poop, brown)
    case "tired": picture = (PixelMap.zzz, Palette.muted)
    case "bored": picture = (PixelMap.bored, Palette.white)
    default: picture = nil
    }
    guard let picture else { return nil }
    return AnyView(
      PixelMap(rows: picture.0, dot: 2, color: picture.1)
        .padding(3)
        .background(Rectangle().fill(Palette.tile)))
  }

  private func buttons(_ pet: PetInfo) -> some View {
    let awake = !pet.asleep
    return VStack(spacing: 4) {
      HStack(spacing: 4) {
        ChoiceButton(title: "Feed", icon: PixelIcon.food, loud: pet.need == "food", enabled: awake) {
          m.petAct("pet-feed")
        }
        if pet.sick {
          ChoiceButton(title: "Heal", icon: PixelIcon.plus, loud: true, enabled: awake) {
            m.petAct("pet-heal")
          }
        } else {
          ChoiceButton(title: "Hunt bugs", icon: PixelIcon.bug, loud: pet.need == "bored", enabled: awake && m.asks.isEmpty) {
            m.startHunt()
          }
        }
      }
      HStack(spacing: 4) {
        ChoiceButton(title: "Clean", icon: PixelIcon.broom, loud: pet.need == "mess", enabled: awake && pet.poops > 0) {
          m.petAct("pet-clean")
        }
        ChoiceButton(
          title: awake ? "Sleep" : "Wake up", icon: awake ? PixelIcon.moon : PixelIcon.sun,
          loud: !awake || pet.need == "tired", enabled: true
        ) { m.petAct("pet-sleep") }
      }
    }
  }
}

extension PetInfo {
  /// What the bubble means, in words. Most urgent first, as the daemon decides.
  var mood: String {
    if asleep { return "asleep" }
    switch need {
    case "sick": return "feeling ill"
    case "food": return "hungry"
    case "mess": return poops == 1 ? "made a mess" : "made \(poops) messes"
    case "tired": return "tired"
    case "bored": return "bored"
    default: return "doing fine"
    }
  }
}
