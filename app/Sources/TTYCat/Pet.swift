// Bit in the panel: the board's home screen.
//
// The pet's life is all in the daemon (daemon/petstate.py), so the board and this page are two
// views of the same pet. It never makes a sound and never sends a notification: those mean an
// agent needs you.
import SwiftUI

/// The board's rule for when a prompt takes over: whoever was clicking is still clicking, and the
/// next thing under the pointer may be Allow. So nothing on a prompt works until a moment has passed
/// and the clicks have stopped.
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

// ---------------------------------------------------------------- sprites

/// firmware/main/pet.c's little pictures: one string per row, "o" lit.
struct PixelMap: View {
  static let heart = [".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."]

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

// ---------------------------------------------------------------- the page

/// A pat, a hello or a finished turn: shown here and on the board alike. Timings are firmware/main/pet.c's.
struct PetEvent: Equatable {
  enum Kind: String {
    case heart, rested, welcome, birthday, reward
    var isHello: Bool { self == .rested || self == .welcome || self == .birthday }
  }
  let kind: Kind
  let at: Date
  var turns = 0
  var levelUp = false

  static let hopFor: TimeInterval = 0.42
  static let floatFor: TimeInterval = 1.3
  static let bannerFor: TimeInterval = 4

  var hops: Int {
    switch kind {
    case .reward: return min(max(turns, 1), 5)
    case .rested: return 3
    case .welcome, .birthday: return 5
    default: return 2
    }
  }
  var lasts: TimeInterval {
    switch kind {
    case .reward: return levelUp ? Self.bannerFor : Double(hops) * Self.hopFor
    case .rested, .welcome, .birthday: return Self.bannerFor
    default: return Self.floatFor
    }
  }
}

/// How Bit looks, by the board's rules (pet_draw in firmware/main/pet.c), so the two agree. Where it
/// happens to wander on the board's screen is the one thing that isn't shared.
enum PetLook {
  /// Night or a dim screen sends it to sleep, unless there's work on.
  static func asleep(pet: PetInfo, working: Int, boardDim: Bool) -> Bool {
    (pet.asleep || boardDim) && working == 0
  }

  static func pose(pet: PetInfo, working: Int, boardDim: Bool, event: PetEvent?, now: Date) -> BitPose {
    if let event {
      let age = now.timeIntervalSince(event.at)
      if age < Double(event.hops) * PetEvent.hopFor { return .happy }
      if event.levelUp || event.kind.isHello, age < PetEvent.bannerFor { return .happy }
    }
    if asleep(pet: pet, working: working, boardDim: boardDim) { return .nap }
    return working > 0 ? .work : .idle
  }

  /// Small ones at laptops: one for each agent Bit isn't already working for.
  static func helpers(pet: PetInfo, working: Int, boardDim: Bool) -> Int {
    min(6, max(0, asleep(pet: pet, working: working, boardDim: boardDim) ? working : working - 1))
  }

  /// The board's line under the pet.
  static func caption(pet: PetInfo, working: Int, done: Int) -> String {
    if done > 0 { return "\(done) done \u{B7} \(working) working" }
    if working > 0 { return "\(working) agent\(working == 1 ? "" : "s") working" }
    return "\(pet.today) turn\(pet.today == 1 ? "" : "s") today"
  }

  /// How high it is in a hop, in dots.
  static func lift(event: PetEvent?, now: Date) -> Int {
    guard let event else { return 0 }
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
      if let pet = m.status?.pet {
        home(pet)
      } else {
        Text("The daemon isn't running, so Bit isn't here.")
          .font(Pixel.body).foregroundStyle(Palette.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .pixelBox(Palette.tile, border: Palette.line)
      }
    }
    .onAppear { m.petPageOpen(true) }
    .onDisappear { m.petPageOpen(false) }
  }

  private func home(_ pet: PetInfo) -> some View {
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
      Text(PetLook.caption(pet: pet, working: m.working, done: m.rows.filter { $0.s == "done" }.count))
        .font(Pixel.small).foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: 4) {
          Text(mood(pet)).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
          ForEach(0..<helpers, id: \.self) { i in BitView(pose: .work, dot: 1, seed: i + 1) }
        }
        .frame(height: 14)
        Spacer(minLength: 2)
        LevelProgress(pet: pet)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(8)
    .frame(height: 112)
    .pixelBox(Palette.card, border: Palette.line)
  }

  private func mood(_ pet: PetInfo) -> String {
    if m.working > 0 { return "at work" }
    if !pet.asleep, boardDim { return "dozing" }  // only as deep as the board's dim screen
    return pet.mood
  }

  private func bit(_ pet: PetInfo, now: Date) -> some View {
    let event = m.petEvent.flatMap { now.timeIntervalSince($0.at) < $0.lasts ? $0 : nil }
    let pose = PetLook.pose(pet: pet, working: m.working, boardDim: boardDim, event: event, now: now)
    let age = event.map { now.timeIntervalSince($0.at) } ?? 0
    let lift = PetLook.lift(event: event, now: now)
    return ZStack(alignment: .topTrailing) {
      BitView(pose: pose, dot: 5, level: pet.level, birthday: pet.birthday, scarf: pet.age >= 100, headroom: 3)
        .offset(y: CGFloat(-lift) * 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
      if let event, event.levelUp, age < PetEvent.bannerFor {
        Caps("Level \(pet.level)", color: Palette.green).frame(maxWidth: .infinity, alignment: .topLeading).padding(4)
      } else if let event, event.kind.isHello, event.kind != .birthday, age < PetEvent.bannerFor {  // the mood says that one
        Caps("Welcome back", color: Palette.green).frame(maxWidth: .infinity, alignment: .topLeading).padding(4)
      } else if pose == .nap {
        zees(now: now)
      } else if pose == .work {
        workBits(now: now)
      }
      if let event { floating(event, age: age) }
    }
  }

  /// What it felt.
  @ViewBuilder private func floating(_ event: PetEvent, age: TimeInterval) -> some View {
    let t = min(1, age / event.lasts)
    if event.kind == .heart, age < PetEvent.floatFor {
      PixelMap(rows: PixelMap.heart, dot: 2, color: Palette.white)
        .frame(maxWidth: .infinity, alignment: .center).offset(y: 12 - 12 * t)
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
}

/// How far Bit has come, and what the next level brings: the board's home screen says the same.
struct LevelProgress: View {
  let pet: PetInfo
  private let cells = 12

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text("LV \(pet.level)").font(Pixel.body).foregroundStyle(Palette.orange)
        Spacer()
        Text("\(pet.age) day\(pet.age == 1 ? "" : "s") old").font(Pixel.small).foregroundStyle(Palette.muted)
      }
      HStack(spacing: 2) {
        ForEach(0..<cells, id: \.self) { i in
          Rectangle().fill(i < pet.progress(of: cells) ? Palette.orange : Palette.dotOff).frame(height: 8)
        }
      }
      Text(pet.nextKeepsake).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
    }
  }
}

extension PetInfo {
  var mood: String {
    if asleep { return "asleep" }
    return birthday ? "happy birthday" : "doing fine"
  }

  /// pet_progress in firmware/main/pet.c.
  func progress(of cells: Int) -> Int {
    let n = level, from = 3 * (n - 1) * (n - 1), to = 3 * n * n
    return ((grown ?? total) - from) * cells / (to - from)
  }

  /// next_keepsake in firmware/main/ui.c.
  var nextKeepsake: String {
    level < 3 ? "headset at level 3" : level < 5 ? "antenna at level 5" : level < 8 ? "crown at level 8" : "wearing its crown"
  }
}
