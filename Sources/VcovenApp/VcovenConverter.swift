import CryptoKit
import Foundation

enum ConversionError: LocalizedError {
    case invalidResource(String)
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidResource(let name): "缺少应用资源：\(name)"
        case .commandFailed(let name, let output): "\(name) 执行失败：\(output)"
        }
    }
}

struct VcovenConverter: Sendable {
    private let resources: URL

    init(resources: URL = Bundle.module.resourceURL!) {
        let nested = resources.appendingPathComponent("Resources")
        self.resources = FileManager.default.fileExists(atPath: nested.appendingPathComponent("config_block.bin").path)
            ? nested : resources
    }

    func build(_ identity: BuildIdentity) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("vcoven-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let rom = try Data(contentsOf: identity.romURL)
        let config = try resource("config_block.bin")
        let code = buildCode(rom: rom, config: config)

        var header = try resource("ncchheader.bin")
        let titleID = UInt64(identity.titleID, radix: 16)!
        header.writeLE(titleID, at: 0x108)
        header.writeLE(titleID, at: 0x118)
        header.replaceFixed(identity.productCode.data(using: .ascii)!, at: 0x150, count: 16)
        header[0x18f] |= 0x04

        var exheader = try resource("exheader.bin")
        exheader.replaceFixed(identity.productCode.dropFirst(6).data(using: .ascii)!, at: 0, count: 8)
        exheader.writeLE(titleID, at: 0x1c8)
        exheader.writeLE(titleID, at: 0x200)

        var icon = try resource("icon.icn")
        patchTitles(&icon, title: identity.title)
        let exefs = packExeFS([
            (".code", code),
            ("banner", try resource("banner.bnr")),
            ("icon", icon),
            ("logo", try resource("logo.darc.lz")),
        ])

        try header.write(to: work.appendingPathComponent("ncchheader.bin"))
        try exheader.write(to: work.appendingPathComponent("exheader.bin"))
        try exefs.write(to: work.appendingPathComponent("exefs.bin"))
        try resource("romfs.bin").write(to: work.appendingPathComponent("romfs.bin"))

        let cxi = work.appendingPathComponent("new.cxi")
        try run("3dstool", ["-ctf", "cxi", cxi.path,
             "--header", work.appendingPathComponent("ncchheader.bin").path,
             "--exh", work.appendingPathComponent("exheader.bin").path,
             "--exefs", work.appendingPathComponent("exefs.bin").path,
             "--romfs", work.appendingPathComponent("romfs.bin").path,
             "--not-encrypt"])
        try fixHashes(at: cxi)

        if fm.fileExists(atPath: identity.outputURL.path) {
            try fm.removeItem(at: identity.outputURL)
        }
        try run("makerom", ["-f", "cia", "-o", identity.outputURL.path,
                            "-content", "\(cxi.path):0:0", "-ignoresign"])
    }

    private func resource(_ name: String) throws -> Data {
        let url = resources.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConversionError.invalidResource(name)
        }
        return try Data(contentsOf: url)
    }

    private func tool(_ name: String) throws -> URL {
        let url = resources.appendingPathComponent("Tools/\(name)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ConversionError.invalidResource(name)
        }
        return url
    }

    private func run(_ name: String, _ arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = try tool(name)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ConversionError.commandFailed(name, output.suffix(800).description)
        }
    }

    private func buildCode(rom: Data, config: Data) -> Data {
        var cfg = config
        cfg.writeLE(UInt32(rom.count), at: 4)
        cfg.writeLE(detectSaveType(in: rom), at: 8)
        var result = rom + cfg + Data(repeating: 0, count: 12)
        result.appendLE(UInt32(0)); result.appendLE(UInt32(0))
        result.appendLE(UInt32(rom.count)); result.appendLE(UInt32(0))
        result.appendLE(UInt32(1)); result.appendLE(UInt32(rom.count))
        result.appendLE(UInt32(0x324)); result.appendLE(UInt32(0))
        result.append(Data(".CAA".utf8))
        result.appendLE(UInt32(1))
        result.appendLE(UInt32(rom.count + 0x324 + 12))
        result.appendLE(UInt32(32))
        return result
    }

    private func detectSaveType(in rom: Data) -> UInt32 {
        func contains(_ text: String) -> Bool { rom.range(of: Data(text.utf8)) != nil }
        if contains("FLASH1M_V") { return 0x0A }
        if contains("FLASH512_V") || contains("FLASH_V") { return 0x04 }
        if contains("EEPROM_V") { return 0x02 }
        if contains("SRAM_V") || contains("SRAM_F_V") { return 0x0E }
        return 0xFF
    }

    private func patchTitles(_ icon: inout Data, title: String) {
        func utf16(_ text: String, bytes: Int) -> Data {
            var data = text.prefix(bytes / 2 - 1).data(using: .utf16LittleEndian)!
            data.append(Data(repeating: 0, count: bytes - data.count))
            return data
        }
        let short = utf16(title, bytes: 0x80)
        let long = utf16(title, bytes: 0x100)
        let publisher = utf16("Homebrew", bytes: 0x80)
        for index in 0..<16 {
            let base = 8 + index * 0x200
            icon.replaceSubrange(base..<(base + 0x80), with: short)
            icon.replaceSubrange((base + 0x80)..<(base + 0x180), with: long)
            icon.replaceSubrange((base + 0x180)..<(base + 0x200), with: publisher)
        }
    }

    private func packExeFS(_ files: [(String, Data)]) -> Data {
        var header = Data(repeating: 0, count: 0x200)
        var body = Data()
        var offset: UInt32 = 0
        for (index, file) in files.enumerated() {
            header.replaceFixed(Data(file.0.utf8), at: index * 16, count: 8)
            header.writeLE(offset, at: index * 16 + 8)
            header.writeLE(UInt32(file.1.count), at: index * 16 + 12)
            let digest = Data(SHA256.hash(data: file.1))
            header.replaceSubrange((0xC0 + (9 - index) * 0x20)..<(0xE0 + (9 - index) * 0x20), with: digest)
            body.append(file.1)
            let padding = (0x200 - file.1.count % 0x200) % 0x200
            body.append(Data(repeating: 0, count: padding))
            offset += UInt32(file.1.count + padding)
        }
        return header + body
    }

    private func fixHashes(at url: URL) throws {
        var cxi = try Data(contentsOf: url)
        let exheaderSize: UInt32 = cxi.readLE(at: 0x180)
        cxi.replaceSubrange(0x160..<0x180, with: Data(SHA256.hash(data: cxi.subdata(in: 0x200..<(0x200 + Int(exheaderSize))))))
        let exefsOffset: UInt32 = cxi.readLE(at: 0x1a0)
        let exefsSize: UInt32 = cxi.readLE(at: 0x1a8)
        let exefsRange = Int(exefsOffset) * 0x200..<(Int(exefsOffset + exefsSize) * 0x200)
        cxi.replaceSubrange(0x1c0..<0x1e0, with: Data(SHA256.hash(data: cxi.subdata(in: exefsRange))))
        let romfsOffset: UInt32 = cxi.readLE(at: 0x1b0)
        let romfsSize: UInt32 = cxi.readLE(at: 0x1b8)
        if romfsOffset > 0, romfsSize > 0 {
            let range = Int(romfsOffset) * 0x200..<(Int(romfsOffset + romfsSize) * 0x200)
            cxi.replaceSubrange(0x1e0..<0x200, with: Data(SHA256.hash(data: cxi.subdata(in: range))))
        }
        cxi[0x18f] |= 0x04
        try cxi.write(to: url)
    }
}

private extension Data {
    mutating func replaceFixed(_ value: Data, at offset: Int, count: Int) {
        replaceSubrange(offset..<(offset + count), with: value.prefix(count) + Data(repeating: 0, count: Swift.max(0, count - value.count)))
    }

    mutating func writeLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        subdata(in: offset..<(offset + MemoryLayout<T>.size)).withUnsafeBytes { $0.loadUnaligned(as: T.self).littleEndian }
    }
}
