import Foundation
import Testing
@testable import TTYCat

@Test func applicationsIsWhereItCanUpdateItself() {
  let home = "/Users/someone"
  #expect(AppMover.isInApplications(URL(fileURLWithPath: "/Applications/ttycat.app"), home: home))
  #expect(AppMover.isInApplications(URL(fileURLWithPath: "/Users/someone/Applications/ttycat.app"), home: home))
  #expect(!AppMover.isInApplications(URL(fileURLWithPath: "/Volumes/ttycat/ttycat.app"), home: home))
  #expect(!AppMover.isInApplications(URL(fileURLWithPath: "/Users/someone/Downloads/ttycat.app"), home: home))
  #expect(!AppMover.isInApplications(URL(fileURLWithPath: "/ApplicationsOld/ttycat.app"), home: home))
}

@Test func itGoesToApplicationsOrTheirOwnIfTheyCantWriteThere() {
  let app = URL(fileURLWithPath: "/Volumes/ttycat/ttycat.app")
  #expect(AppMover.destination(for: app, home: "/Users/x", writable: { _ in true }).path == "/Applications/ttycat.app")
  #expect(AppMover.destination(for: app, home: "/Users/x", writable: { _ in false }).path == "/Users/x/Applications/ttycat.app")
}

@Test func onlyTheDiskImageItIsOnIsEjected() {
  let info: [String: Any] = ["images": [
    ["system-entities": [["dev-entry": "/dev/disk4"], ["dev-entry": "/dev/disk4s1", "mount-point": "/Volumes/ttycat"]]],
    ["system-entities": [["dev-entry": "/dev/disk5s1", "mount-point": "/Volumes/ttycat 1"]]],
  ]]
  #expect(AppMover.mountPoint(of: "/Volumes/ttycat/ttycat.app", in: info) == "/Volumes/ttycat")
  #expect(AppMover.mountPoint(of: "/Volumes/ttycat 1/ttycat.app", in: info) == "/Volumes/ttycat 1")
  #expect(AppMover.mountPoint(of: "/Volumes/Backup/ttycat.app", in: info) == nil)  // a drive of theirs: never
}

@Test func anAppThatIsntTranslocatedIsWhereItIs() {
  let app = URL(fileURLWithPath: "/Users/x/Downloads/ttycat.app")
  #expect(AppMover.untranslocated(app) == app)
}
