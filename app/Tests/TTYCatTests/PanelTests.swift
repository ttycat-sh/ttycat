import AppKit
import Testing
@testable import TTYCat

// A 1728 x 1117 screen with a 37-point menu bar, in AppKit's coordinates: y grows upwards.
private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080)
private let icon = CGRect(x: 1016, y: 1080, width: 40, height: 37)

@Test func theTopStaysUnderTheIconAtAnyHeight() {
  for height: CGFloat in [120, 413, 683, 1000] {
    let frame = PanelPlacement.frame(button: icon, visible: visible, width: 320, height: height)
    #expect(frame.maxY == icon.minY - PanelPlacement.gap)
    #expect(frame.height == height)
  }
}

@Test func tooTallStopsAtTheBottomOfTheScreen() {
  let frame = PanelPlacement.frame(button: icon, visible: visible, width: 320, height: 5000)
  #expect(frame.minY == visible.minY + PanelPlacement.margin)
  #expect(frame.height == PanelPlacement.tallest(button: icon, visible: visible))
}

@Test func itStaysOnScreenAtTheRightEdge() {
  let right = CGRect(x: 1700, y: 1080, width: 28, height: 37)
  let frame = PanelPlacement.frame(button: right, visible: visible, width: 320, height: 400)
  #expect(frame.maxX == visible.maxX - PanelPlacement.margin)
}

@Test func itWorksOnASecondScreenToTheLeft() {
  let left = CGRect(x: -1920, y: 0, width: 1920, height: 1040)
  let button = CGRect(x: -500, y: 1040, width: 40, height: 40)
  let frame = PanelPlacement.frame(button: button, visible: left, width: 320, height: 400)
  #expect(frame.minX == -500)
  #expect(frame.maxY == 1039)
}
