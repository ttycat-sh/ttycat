// Bit, the board's mascot: the same 16x14 sprite as firmware/main/pet.c, for the panel,
// the menu bar and the app icon.
import AppKit
import SwiftUI

enum BitPose { case idle, blink, work, alert, happy, nap }

enum Ink { case body, shade, eye, glint, laptop, edge, logo, hand, gold, bulb }

struct BitCell {
  let x: Int, y: Int, w: Int, h: Int
  let ink: Ink
}

private let bodyRows = [
  "..oo........oo..",
  "..ooo......ooo..",
  "..oooooooooooo..",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".oooooooooooooo.",
  ".dooooooooooood.",
  "..dddddddddddd..",
]

// `tick` moves the hands and the laptop's light; `seed` keeps several from typing in step.
func bitCells(_ pose: BitPose, tick: Int = 0, seed: Int = 0, level: Int = 0, birthday: Bool = false, scarf: Bool = false) -> [BitCell] {
  var out: [BitCell] = []
  func put(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ ink: Ink) { out.append(BitCell(x: x, y: y, w: w, h: h, ink: ink)) }

  // Lying down, it loses two rows and its feet, and sits lower.
  let shown = pose == .nap ? (0..<12).filter { $0 != 3 && $0 != 4 } : Array(0..<12)
  let top = 14 - shown.count - (pose == .nap ? 0 : 2)
  var rowY = [Int: Int]()
  for (i, r) in shown.enumerated() {
    let y = top + i
    rowY[r] = y
    let row = Array(bodyRows[r])
    for c in 0..<16 where row[c] != "." { put(c, y, 1, 1, row[c] == "d" ? .shade : .body) }
  }
  let ry = { (r: Int) in rowY[r] ?? 0 }

  if pose != .nap && pose != .work {
    put(3, 12, 2, 2, .body)
    put(11, 12, 2, 2, .body)
  }
  if pose != .nap && pose != .work {  // arms
    let up = pose == .happy || pose == .alert
    put(0, ry(up ? 5 : 8), 1, 2, up ? .body : .shade)
    put(15, ry(up ? 5 : 8), 1, 2, up ? .body : .shade)
  }

  switch pose {
  case .idle:
    put(4, ry(5), 2, 3, .eye)
    put(10, ry(5), 2, 3, .eye)
    put(4, ry(5), 1, 1, .glint)
    put(10, ry(5), 1, 1, .glint)
    put(7, ry(9), 2, 1, .shade)
  case .blink:
    put(4, ry(7), 2, 1, .eye)
    put(10, ry(7), 2, 1, .eye)
    put(7, ry(9), 2, 1, .shade)
  case .alert:
    put(4, ry(4), 2, 4, .eye)
    put(10, ry(4), 2, 4, .eye)
    put(4, ry(4), 1, 1, .glint)
    put(10, ry(4), 1, 1, .glint)
    put(6, ry(8), 4, 2, .eye)
  case .happy:
    for c in [3, 10] {
      put(c, ry(6), 1, 1, .eye)
      put(c + 1, ry(5), 1, 1, .eye)
      put(c + 2, ry(6), 1, 1, .eye)
    }
    put(2, ry(8), 2, 1, .shade)
    put(12, ry(8), 2, 1, .shade)
    put(6, ry(8), 4, 1, .eye)
    put(7, ry(9), 2, 1, .eye)
  case .nap:
    put(3, ry(6), 3, 1, .eye)
    put(10, ry(6), 3, 1, .eye)
  case .work:
    let blink = (tick + seed * 7) % 40 == 0
    put(4, blink ? 7 : 6, 2, blink ? 1 : 2, .eye)
    put(10, blink ? 7 : 6, 2, blink ? 1 : 2, .eye)
    // Its hands take turns on the keys, either side of the lid.
    let leftDown = (tick + seed) % 2 == 0
    put(1, leftDown ? 10 : 9, 2, 2, .hand)
    put(13, leftDown ? 9 : 10, 2, 2, .hand)
    put(3, 8, 10, 5, .laptop)
    put(2, 13, 12, 1, .edge)
    put(7, 10, 2, 1, (tick / 4 + seed) % 2 == 0 ? .edge : .logo)
  }

  // What it has earned, as on the board: a headset at 3, an antenna at 5, a crown at 8.
  if level >= 3 {
    put(4, ry(1), 8, 1, .glint)
    put(0, ry(5), 2, 3, .glint)
    put(14, ry(5), 2, 3, .glint)
    if pose == .idle || pose == .blink { put(12, ry(9), 2, 1, .glint) }  // its microphone
  }
  if scarf && pose != .work && pose != .nap {  // what it keeps from its first 100 days
    put(1, ry(10), 14, 1, .bulb)
    put(10, ry(10) + 1, 2, 1, .bulb)
  }
  if birthday {  // a party hat, for the day, in place of whatever it has earned up there
    put(5, ry(1) - 1, 6, 1, .gold)
    put(6, ry(1) - 2, 4, 1, .glint)
    put(7, ry(1) - 3, 2, 1, .gold)
  } else if level >= 8 {
    put(5, ry(1) - 1, 6, 1, .gold)
    put(5, ry(1) - 2, 1, 1, .gold)
    put(7, ry(1) - 2, 2, 1, .gold)
    put(10, ry(1) - 2, 1, 1, .gold)
  } else if level >= 5 {
    put(7, ry(1) - 2, 2, 2, .edge)
    put(7, ry(1) - 3, 2, 1, tick / 3 % 2 == 0 ? .glint : .bulb)
  }
  return out
}

struct BitView: View {
  let pose: BitPose
  var dot: CGFloat = 2
  var seed = 0
  var dimmed = false
  var level = 0
  var birthday = false
  var scarf = false
  var headroom = 0  // rows above it, for an antenna or a crown

  var body: some View {
    // Blinks and typing run off the clock, so only poses that move need one.
    TimelineView(.periodic(from: .now, by: 0.17)) { context in
      let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.17)
      let shown: BitPose = pose == .idle && tick % 30 == 0 ? .blink : pose
      Canvas { ctx, _ in
        for c in bitCells(shown, tick: tick, seed: seed, level: level, birthday: birthday, scarf: scarf) {
          let r = CGRect(
            x: CGFloat(c.x) * dot, y: CGFloat(c.y + headroom) * dot, width: CGFloat(c.w) * dot, height: CGFloat(c.h) * dot)
          ctx.fill(Path(r), with: .color(color(c.ink)))
        }
      }
    }
    .frame(width: 16 * dot, height: CGFloat(14 + headroom) * dot)
    .opacity(dimmed ? 0.45 : 1)
  }

  private func color(_ ink: Ink) -> Color {
    switch ink {
    case .body: return dimmed ? Palette.muted : Palette.bitBody
    case .shade: return dimmed ? Palette.muted2 : Palette.bitShade
    case .eye: return Palette.ink
    case .glint: return Palette.white
    case .laptop: return Palette.laptop
    case .edge: return Palette.laptopEdge
    case .logo: return Palette.bitBody
    case .hand: return Palette.bitShade
    case .gold: return Color(hex: 0xFFD34D)
    case .bulb: return Palette.green
    }
  }
}

// ---------------------------------------------------------------- the menu bar

enum MenuIcon {
  /// Faded = nothing's connected. Otherwise plain, so it follows the menu bar's own colour,
  /// until something needs you: then it's orange, with how many beside it.
  static func make(pose: BitPose, tick: Int, faded: Bool, needs: Int) -> NSImage {
    let cells = bitCells(pose, tick: tick)
    let count = needs > 0 ? NSAttributedString(
      string: "\(needs)",
      attributes: [
        .font: NSFont(name: "Silkscreen-Bold", size: 8) ?? NSFont.systemFont(ofSize: 9),
        .foregroundColor: Look.nsColor(Look.accentValue),
      ]) : nil
    let width = 16 + (count.map { ceil($0.size().width) + 3 } ?? 0)
    let image = NSImage(size: NSSize(width: width, height: 16), flipped: true) { _ in
      for c in cells {
        let rect = NSRect(x: c.x, y: c.y + 1, width: c.w, height: c.h)
        let color = needs > 0 ? solid(c.ink) : template(c.ink, faded: faded)
        color.setFill()
        rect.fill(using: .copy)
      }
      count?.draw(at: NSPoint(x: 19, y: 3))
      return true
    }
    image.isTemplate = needs == 0
    return image
  }

  private static func template(_ ink: Ink, faded: Bool) -> NSColor {
    let scale: CGFloat = faded ? 0.4 : 1
    switch ink {
    case .body: return NSColor(white: 0, alpha: scale)
    case .shade, .hand: return NSColor(white: 0, alpha: 0.7 * scale)
    case .laptop: return NSColor(white: 0, alpha: 0.45 * scale)
    case .edge: return NSColor(white: 0, alpha: 0.7 * scale)
    case .logo, .gold, .bulb: return NSColor(white: 0, alpha: scale)
    case .eye, .glint: return NSColor(white: 0, alpha: 0)  // cut out, so they show the bar
    }
  }

  private static func solid(_ ink: Ink) -> NSColor {
    switch ink {
    case .body, .logo: return Look.nsColor(Look.skin.body)
    case .shade, .hand: return Look.nsColor(Look.skin.shade)
    case .eye: return NSColor(white: 0.04, alpha: 1)
    case .glint: return .white
    case .laptop: return NSColor(white: 0.77, alpha: 1)
    case .edge: return NSColor(white: 0.48, alpha: 1)
    case .gold: return NSColor(srgbRed: 1, green: 0.827, blue: 0.302, alpha: 1)
    case .bulb: return NSColor(srgbRed: 0.247, green: 0.827, blue: 0.541, alpha: 1)
    }
  }

  /// The app icon's PNGs, for iconutil.
  static func writeIconset(to dir: String) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, px) in [
      ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
      ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
    ] {
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      let size = CGFloat(px)
      let step = size / 24
      // A stepped black tile, on the grid Bit's drawn on.
      NSColor.black.setFill()
      NSRect(x: step, y: 0, width: size - 2 * step, height: size).fill()
      NSRect(x: 0, y: step, width: size, height: size - 2 * step).fill()
      let dot = floor(size / 20)
      let ox = (size - 16 * dot) / 2, oy = (size - 14 * dot) / 2
      for c in bitCells(.idle) {
        solid(c.ink).setFill()
        NSRect(
          x: ox + CGFloat(c.x) * dot, y: size - oy - CGFloat(c.y + c.h) * dot, width: CGFloat(c.w) * dot,
          height: CGFloat(c.h) * dot
        ).fill()
      }
      NSGraphicsContext.restoreGraphicsState()
      try rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
    }
  }
}
