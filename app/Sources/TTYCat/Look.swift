// Bit's colours and the accent, chosen by number: the same tables as firmware/main/gfx.c.
import AppKit
import SwiftUI

struct LookInfo: Decodable, Equatable {
  var skin: Int
  var accent: Int
}

enum Look {
  struct Skin {
    let name: String
    let body: UInt32
    let shade: UInt32
  }
  struct Accent {
    let name: String
    let value: UInt32
  }

  static let skins = [
    Skin(name: "Ember", body: 0xFF6A13, shade: 0xB84A0C),
    Skin(name: "Mint", body: 0x3FD38A, shade: 0x1F8F58),
    Skin(name: "Ice", body: 0x5AB8FF, shade: 0x2E78B8),
    Skin(name: "Grape", body: 0xB07CFF, shade: 0x7443C4),
    Skin(name: "Rose", body: 0xFF6FA8, shade: 0xB83E72),
    Skin(name: "Mono", body: 0xD8D8D8, shade: 0x8A8A8A),
  ]
  static let accents = [
    Accent(name: "Orange", value: 0xFF6A13),
    Accent(name: "Teal", value: 0x2DD4BF),
    Accent(name: "Blue", value: 0x5AB8FF),
    Accent(name: "Violet", value: 0xB07CFF),
    Accent(name: "Yellow", value: 0xFFC83D),
  ]

  private(set) static var current = LookInfo(skin: 0, accent: 0)

  static func apply(_ look: LookInfo?) {
    guard let look else { return }
    current = LookInfo(
      skin: skins.indices.contains(look.skin) ? look.skin : 0,
      accent: accents.indices.contains(look.accent) ? look.accent : 0)
  }

  static var skin: Skin { skins[current.skin] }
  static var accentValue: UInt32 { accents[current.accent].value }

  static func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }
}
