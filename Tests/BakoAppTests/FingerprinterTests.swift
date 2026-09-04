import XCTest
@testable import BakoApp

final class FingerprinterTests: XCTestCase {
    func testFingerprintIsStableAcrossCreationOrderAndTimestamps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let left = root.appendingPathComponent("left")
        let right = root.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("name: demo".utf8).write(to: left.appendingPathComponent("SKILL.md"))
        try Data("payload".utf8).write(to: left.appendingPathComponent("data.txt"))
        try Data("payload".utf8).write(to: right.appendingPathComponent("data.txt"))
        try Data("name: demo".utf8).write(to: right.appendingPathComponent("SKILL.md"))

        XCTAssertEqual(try Fingerprinter.fingerprint(of: left), try Fingerprinter.fingerprint(of: right))
    }

    func testSymlinkTextChangesFingerprint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let left = root.appendingPathComponent("left")
        let right = root.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createSymbolicLink(atPath: left.appendingPathComponent("ref").path, withDestinationPath: "one")
        try FileManager.default.createSymbolicLink(atPath: right.appendingPathComponent("ref").path, withDestinationPath: "two")
        XCTAssertNotEqual(try Fingerprinter.fingerprint(of: left), try Fingerprinter.fingerprint(of: right))
    }
}
