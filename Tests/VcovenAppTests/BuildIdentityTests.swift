import Foundation
import Testing
@testable import VcovenApp

@Test func acceptsOnlyGBAFilesAndRemovesDuplicates() {
    let urls = [
        URL(fileURLWithPath: "/tmp/One.gba"),
        URL(fileURLWithPath: "/tmp/readme.txt"),
        URL(fileURLWithPath: "/tmp/Two.GBA"),
        URL(fileURLWithPath: "/tmp/One.gba"),
    ]

    #expect(BuildIdentity.acceptedROMs(from: urls).map(\.lastPathComponent) == ["One.gba", "Two.GBA"])
}

@Test func derivesStableMetadataAndAdjacentOutput() {
    let rom = URL(fileURLWithPath: "/Games/Advance Wars.gba")
    let first = BuildIdentity(for: rom)
    let second = BuildIdentity(for: rom)

    #expect(first.title == "Advance Wars")
    #expect(first.outputURL.path == "/Games/Advance Wars.cia")
    #expect(first.titleID == second.titleID)
    #expect(first.titleID.range(of: #"^000400000F[0-9A-F]{6}$"#, options: .regularExpression) != nil)
    #expect(first.productCode.range(of: #"^CTR-N-[0-9A-F]{4}$"#, options: .regularExpression) != nil)
}

@Test func buildsCIAEndToEnd() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vcoven-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let romURL = directory.appendingPathComponent("Test Game.gba")
    var rom = Data(repeating: 0, count: 1024 * 1024)
    rom.replaceSubrange(0xA0..<0xAC, with: Data("TEST GAME   ".utf8))
    try rom.write(to: romURL)

    let identity = BuildIdentity(for: romURL)
    try VcovenConverter().build(identity)

    let attributes = try FileManager.default.attributesOfItem(atPath: identity.outputURL.path)
    #expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > rom.count)
}
