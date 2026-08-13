import AppKit
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

@Test func acceptsSupportedGBAAndSNESROMs() {
    let urls = ["One.gba", "Two.sfc", "Three.SMC", "readme.txt"].map { URL(fileURLWithPath: "/tmp/\($0)") }
    #expect(BuildIdentity.acceptedROMs(from: urls).map(\.pathExtension) == ["gba", "sfc", "SMC"])
    #expect(BuildConfiguration(romURL: urls[0]).platform == .gba)
    #expect(BuildConfiguration(romURL: urls[1]).platform == .snes)
}

@Test func derivesStableMetadataAndAdjacentOutput() {
    let rom = URL(fileURLWithPath: "/Games/Advance Wars.gba")
    let first = BuildIdentity(for: rom)
    let second = BuildIdentity(for: rom)

    #expect(first.title == "Advance Wars")
    #expect(first.outputURL.path == "/Games/Advance Wars.cia")
    #expect(first.titleID == second.titleID)
    #expect(first.titleID.range(of: #"^000400000F[0-9A-F]{4}00$"#, options: .regularExpression) != nil)
    #expect(first.productCode.range(of: #"^CTR-N-[0-9A-F]{4}$"#, options: .regularExpression) != nil)
}

@Test func editableConfigurationValidatesAndRandomizesTitleID() {
    let rom = URL(fileURLWithPath: "/Games/Advance Wars.gba")
    var configuration = BuildConfiguration(romURL: rom)
    let original = configuration.titleID

    #expect(configuration.validationMessage == "请选择 256×128 横幅")
    configuration.bannerURL = URL(fileURLWithPath: "/tmp/banner.png")
    #expect(configuration.validationMessage == nil)

    configuration.randomizeTitleID()
    #expect(configuration.titleID != original)
    #expect(configuration.titleID.range(of: #"^000400000F[0-9A-F]{4}00$"#, options: .regularExpression) != nil)
}

@Test func generatesExactDefaultTextIcon() throws {
    let png = try ArtworkGenerator.textIconPNG(title: "龙珠大冒险", side: 48)
    let image = try #require(NSBitmapImageRep(data: png))
    #expect(image.pixelsWide == 48)
    #expect(image.pixelsHigh == 48)
    #expect(png.count > 500)
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

@Test func buildsSNESCIAEndToEnd() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vcoven-snes-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let romURL = directory.appendingPathComponent("Test Game.sfc")
    try Data(repeating: 0, count: 1024 * 1024).write(to: romURL)
    var configuration = BuildConfiguration(romURL: romURL)
    configuration.bannerURL = Bundle.module.url(forResource: "default-banner", withExtension: "png", subdirectory: "Resources")
    try VcovenConverter().build(configuration)

    let attributes = try FileManager.default.attributesOfItem(atPath: configuration.outputURL.path)
    #expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > romURL.fileSize)
}

private extension URL {
    var fileSize: Int { (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}
