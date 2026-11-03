// The board's look: its palette, its four pixel fonts, its stepped-corner boxes and 5x5 icons.
import AppKit
import CoreText
import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
}

// The same values as firmware/main/ui.c.
enum Palette {
  static let black = Color(hex: 0x000000)
  static let tile = Color(hex: 0x0C0C0C)
  static let line = Color(hex: 0x262626)
  static let dotOff = Color(hex: 0x1C1C1C)
  static let card = Color(hex: 0x161616)
  static let code = Color(hex: 0x0B0B0B)
  static let muted = Color(hex: 0x9A9A9A)
  static let muted2 = Color(hex: 0x8C8C8C)
  static let faint = Color(hex: 0x505050)
  static let white = Color(hex: 0xFFFFFF)
  static var orange: Color { Color(hex: Look.accentValue) }  // the accent: orange unless you've chosen otherwise
  static var bitBody: Color { Color(hex: Look.skin.body) }
  static var bitShade: Color { Color(hex: Look.skin.shade) }
  static let green = Color(hex: 0x3FD38A)
  static let laptop = Color(hex: 0xC4C4C4)
  static let laptopEdge = Color(hex: 0x7A7A7A)
  static let ink = Color(hex: 0x0B0B0B)
}

enum Pixel {
  static func registerFonts() {
    for name in ["Silkscreen-Bold", "PressStart2P-Regular", "VT323-Regular", "PixelifySans-wght"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }

  // The firmware's type roles.
  static let label = Font.custom("Silkscreen-Bold", fixedSize: 8)
  static let button = Font.custom("Silkscreen-Bold", fixedSize: 8)
  static let hero = Font.custom("PressStart2P-Regular", fixedSize: 16)
  static let body = Font.custom("VT323-Regular", fixedSize: 16)
  static let small = Font.custom("VT323-Regular", fixedSize: 14)

  // A variable font: the board draws Pixelify Sans at weight 700.
  static var title: Font {
    let wght = 0x7767_6874  // 'wght'
    let base = NSFontDescriptor(name: "PixelifySans-Regular", size: 16)
    let bold = base.addingAttributes([.variation: [NSNumber(value: wght): NSNumber(value: 700)]])
    return NSFont(descriptor: bold, size: 16).map { Font($0) } ?? .custom("PixelifySans-Regular", fixedSize: 16)
  }
}

// The board's `.n` box: a fill, an optional 2 px border, and 2x2 steps cut from the corners.
struct SteppedRect: Shape {
  var step: CGFloat = 2
  func path(in r: CGRect) -> Path {
    Path { p in
      p.move(to: CGPoint(x: r.minX + step, y: r.minY))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.minY))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.maxX, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.maxY))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.maxY))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.minX, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.minX, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.minY + step))
      p.closeSubpath()
    }
  }
}

extension View {
  func pixelBox(_ fill: Color, border: Color? = nil) -> some View {
    background(
      ZStack {
        SteppedRect().fill(border ?? fill)
        if border != nil { Rectangle().fill(fill).padding(2) }
      })
  }
}

// 5x5 icon, one byte per row (low 5 bits, MSB = left): the firmware's format and data.
struct PixelIcon: View {
  static let bang: [UInt8] = [0x04, 0x04, 0x04, 0x00, 0x04]
  static let cross: [UInt8] = [0x11, 0x0A, 0x04, 0x0A, 0x11]
  static let check: [UInt8] = [0x01, 0x03, 0x16, 0x1C, 0x08]
  static let dash: [UInt8] = [0x00, 0x00, 0x0E, 0x00, 0x00]
  static let right: [UInt8] = [0x08, 0x04, 0x02, 0x04, 0x08]
  static let left: [UInt8] = [0x02, 0x04, 0x08, 0x04, 0x02]
  static let food: [UInt8] = [0x04, 0x0E, 0x1F, 0x1F, 0x0E]
  static let plus: [UInt8] = [0x04, 0x04, 0x1F, 0x04, 0x04]
  static let bug: [UInt8] = [0x11, 0x0E, 0x1F, 0x0E, 0x11]
  static let broom: [UInt8] = [0x01, 0x02, 0x04, 0x0E, 0x1F]
  static let moon: [UInt8] = [0x0E, 0x18, 0x18, 0x18, 0x0E]
  static let sun: [UInt8] = [0x15, 0x0E, 0x1F, 0x0E, 0x15]

  let rows: [UInt8]
  var scale: CGFloat = 2
  var color: Color = Palette.white

  var body: some View {
    Canvas { ctx, _ in
      for (j, row) in rows.enumerated() {
        for i in 0..<5 where row & (0x10 >> UInt8(i)) != 0 {
          let r = CGRect(x: CGFloat(i) * scale, y: CGFloat(j) * scale, width: scale, height: scale)
          ctx.fill(Path(r), with: .color(color))
        }
      }
    }
    .frame(width: 5 * scale, height: 5 * scale)
  }
}

// Silkscreen labels are capitals on the board too.
struct Caps: View {
  let text: String
  var color: Color = Palette.muted
  init(_ text: String, color: Color = Palette.muted) {
    self.text = text
    self.color = color
  }
  var body: some View {
    Text(text.uppercased()).font(Pixel.label).foregroundStyle(color).lineLimit(1)
  }
}

// The board's "pressed" feedback: the box lights up while held.
struct PixelPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.brightness(configuration.isPressed ? 0.25 : 0).contentShape(Rectangle())
  }
}

struct PixelButton: View {
  let title: String
  var loud = false
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Caps(title, color: !enabled ? Palette.faint : loud ? Palette.black : Palette.white)
        .frame(maxWidth: .infinity, minHeight: 28)
        .pixelBox(loud && enabled ? Palette.orange : Palette.tile, border: loud && enabled ? nil : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
  }
}

struct PixelCheckbox: View {
  let on: Bool
  var body: some View {
    ZStack {
      Rectangle().fill(on ? Palette.green : Palette.tile)
      Rectangle().strokeBorder(on ? Palette.green : Palette.faint, lineWidth: 2)
      if on { PixelIcon(rows: PixelIcon.check, scale: 2, color: Palette.black) }
    }
    .frame(width: 16, height: 16)
  }
}

// Food, fun, rest on the home screen: eight blocks.
struct PixelMeter: View {
  let label: String
  let value: Int
  var low = false
  var body: some View {
    HStack(spacing: 4) {
      Caps(label)
      HStack(spacing: 2) {
        let filled = value > 0 ? max(1, (value * 8 + 50) / 100) : 0
        ForEach(0..<8, id: \.self) { i in
          Rectangle().fill(i < filled ? (low ? Palette.white : Palette.orange) : Palette.dotOff)
            .frame(width: 5, height: 8)
        }
      }
    }
  }
}
