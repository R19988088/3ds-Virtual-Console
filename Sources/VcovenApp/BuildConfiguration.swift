import CryptoKit
import Foundation

enum ROMPlatform: String, Sendable {
    case gba = "GBA"
    case snes = "SNES"
    case arcade = "街机（FBA）"
}

enum SaveType: String, CaseIterable, Identifiable, Sendable {
    case auto, flash1m, flash512, eeprom8, eeprom64, sram, none

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自动检测"
        case .flash1m: "Flash 1M"
        case .flash512: "Flash 512K"
        case .eeprom8: "EEPROM 8K"
        case .eeprom64: "EEPROM 64K"
        case .sram: "SRAM"
        case .none: "无存档"
        }
    }

    var value: UInt32? {
        switch self {
        case .auto: nil
        case .flash1m: 0x0A
        case .flash512: 0x04
        case .eeprom8: 0x00
        case .eeprom64: 0x02
        case .sram: 0x0E
        case .none: 0xFF
        }
    }
}

struct BuildConfiguration: Identifiable, Sendable {
    let id = UUID()
    let romURL: URL
    let platform: ROMPlatform
    var iconURL: URL?
    var bannerURL: URL?
    var title: String
    var longTitle: String
    var publisher = "Homebrew"
    var titleID: String
    var productCode: String
    var saveType = SaveType.auto
    var state = BuildState.waiting

    init(romURL: URL) {
        self.romURL = romURL
        let ext = romURL.pathExtension.lowercased()
        platform = ext == "gba" ? .gba : (ext == "zip" ? .arcade : .snes)
        let identity = BuildIdentity(for: romURL)
        title = identity.title
        longTitle = identity.title
        titleID = Self.randomTitleID()
        productCode = platform == .gba ? identity.productCode : (platform == .arcade ? "CTR-N-FBA1" : "CTR-N-SNES")
    }

    var outputURL: URL { romURL.deletingPathExtension().appendingPathExtension("cia") }
    var romSize: String {
        let bytes = (try? romURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var validationMessage: String? {
        if bannerURL == nil { return "请选择 256×128 横幅" }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入标题" }
        if titleID.range(of: #"^000400000F[0-9A-Fa-f]{4}00$"#, options: .regularExpression) == nil { return "Title ID 格式应为 000400000FXXXX00" }
        if productCode.range(of: #"^CTR-N-[A-Za-z0-9]{4,10}$"#, options: .regularExpression) == nil { return "产品码格式应为 CTR-N-XXXX" }
        return nil
    }

    mutating func randomizeTitleID() {
        titleID = Self.randomTitleID()
    }

    private static func randomTitleID() -> String {
        let bytes = (0..<2).map { _ in UInt8.random(in: 0...255) }
        return "000400000F" + bytes.map { String(format: "%02X", $0) }.joined() + "00"
    }
}
