import AppKit
import Foundation
import XCTest
@testable import VcovenApp

final class VcovenAppTests: XCTestCase {
func testAcceptsOnlyGBAFilesAndRemovesDuplicates() {
    let urls = [
        URL(fileURLWithPath: "/tmp/One.gba"),
        URL(fileURLWithPath: "/tmp/readme.txt"),
        URL(fileURLWithPath: "/tmp/Two.GBA"),
        URL(fileURLWithPath: "/tmp/One.gba"),
    ]

    XCTAssertEqual(BuildIdentity.acceptedROMs(from: urls).map(\.lastPathComponent), ["One.gba", "Two.GBA"])
}

func testAcceptsSupportedGBAAndSNESROMs() {
    let urls = ["One.gba", "Two.sfc", "Three.SMC", "readme.txt"].map { URL(fileURLWithPath: "/tmp/\($0)") }
    XCTAssertEqual(BuildIdentity.acceptedROMs(from: urls).map(\.pathExtension), ["gba", "sfc", "SMC"])
    XCTAssertEqual(BuildConfiguration(romURL: urls[0]).platform, .gba)
    XCTAssertEqual(BuildConfiguration(romURL: urls[1]).platform, .snes)
}

func testAcceptsArcadeZipROM() {
    let url = URL(fileURLWithPath: "/tmp/Street Fighter.zip")
    XCTAssertEqual(BuildIdentity.acceptedROMs(from: [url]), [url])
    XCTAssertEqual(BuildConfiguration(romURL: url).platform, .arcade)
    XCTAssertEqual(BuildConfiguration(romURL: url).productCode, "CTR-N-FBN1")
}

func testDerivesStableMetadataAndAdjacentOutput() {
    let rom = URL(fileURLWithPath: "/Games/Advance Wars.gba")
    let first = BuildIdentity(for: rom)
    let second = BuildIdentity(for: rom)

    XCTAssertEqual(first.title, "Advance Wars")
    XCTAssertEqual(first.outputURL.path, "/Games/Advance Wars.cia")
    XCTAssertEqual(first.titleID, second.titleID)
    XCTAssertNotNil(first.titleID.range(of: #"^000400000F[0-9A-F]{4}00$"#, options: .regularExpression))
    XCTAssertNotNil(first.productCode.range(of: #"^CTR-N-[0-9A-F]{4}$"#, options: .regularExpression))
}

func testEditableConfigurationValidatesAndRandomizesTitleID() {
    let rom = URL(fileURLWithPath: "/Games/Advance Wars.gba")
    var configuration = BuildConfiguration(romURL: rom)
    let original = configuration.titleID

    XCTAssertEqual(configuration.validationMessage, "请选择 256×128 横幅")
    configuration.bannerURL = URL(fileURLWithPath: "/tmp/banner.png")
    XCTAssertNil(configuration.validationMessage)

    configuration.randomizeTitleID()
    XCTAssertNotEqual(configuration.titleID, original)
    XCTAssertNotNil(configuration.titleID.range(of: #"^000400000F[0-9A-F]{4}00$"#, options: .regularExpression))
}

func testGeneratesExactDefaultTextIcon() throws {
    let png = try ArtworkGenerator.textIconPNG(title: "龙珠大冒险", side: 48)
    let image = try XCTUnwrap(NSBitmapImageRep(data: png))
    XCTAssertEqual(image.pixelsWide, 48)
    XCTAssertEqual(image.pixelsHigh, 48)
    XCTAssertGreaterThan(png.count, 500)
}

func testBuildsCIAEndToEnd() throws {
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
    XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, rom.count)
}

func testBuildsSNESCIAEndToEnd() throws {
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
    XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, romURL.fileSize)
}

func testBuildsArcadeCIAWithRuntimeFixture() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vcoven-arcade-test-\(UUID().uuidString)")
    let resources = directory.appendingPathComponent("Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let bundled = try XCTUnwrap(Bundle.module.resourceURL)
    for item in try FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
        try FileManager.default.copyItem(at: item, to: resources.appendingPathComponent(item.lastPathComponent))
    }
    let arcade = resources.appendingPathComponent("arcade")
    try FileManager.default.createDirectory(at: arcade, withIntermediateDirectories: true)
    let runtime = try XCTUnwrap(Bundle.module.url(forResource: "snes/snes9x_3ds", withExtension: "elf"))
    try FileManager.default.copyItem(at: runtime, to: arcade.appendingPathComponent("fbneo_3ds.elf"))

    let romURL = directory.appendingPathComponent("Test Arcade.zip")
    try Data(repeating: 0x5A, count: 4096).write(to: romURL)
    var configuration = BuildConfiguration(romURL: romURL)
    configuration.bannerURL = resources.appendingPathComponent("default-banner.png")
    try VcovenConverter(resources: directory).build(configuration)

    let attributes = try FileManager.default.attributesOfItem(atPath: configuration.outputURL.path)
    XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, romURL.fileSize)
}
}

private extension URL {
    var fileSize: Int { (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}
