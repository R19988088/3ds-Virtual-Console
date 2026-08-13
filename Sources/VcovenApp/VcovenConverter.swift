import CryptoKit
import AppKit
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

    init(resources: URL? = nil) {
        let resources = resources ?? Self.defaultResourceURL()
        let nested = resources.appendingPathComponent("Resources")
        self.resources = FileManager.default.fileExists(atPath: nested.appendingPathComponent("config_block.bin").path)
            ? nested : resources
    }

    private static func defaultResourceURL() -> URL {
        let fileManager = FileManager.default
        let candidates = [Bundle.main.resourceURL,
                          Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")]
            .compactMap { $0 }
        if let resourceURL = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent("config_block.bin").path)
        }) {
            return resourceURL
        }
        return Bundle.module.resourceURL ?? fileManager.temporaryDirectory
    }

    func build(_ identity: BuildIdentity) throws {
        var configuration = BuildConfiguration(romURL: identity.romURL)
        configuration.bannerURL = resources.appendingPathComponent("default-banner.png")
        try build(configuration)
    }

    func build(_ configuration: BuildConfiguration) throws {
        guard let bannerURL = configuration.bannerURL else { throw ConversionError.invalidResource("横幅") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("vcoven-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let iconURL: URL
        if let selected = configuration.iconURL {
            iconURL = selected
        } else {
            iconURL = work.appendingPathComponent("generated-icon.png")
            try ArtworkGenerator.textIconPNG(title: configuration.title).write(to: iconURL)
        }

        if configuration.platform == .snes {
            try buildSNES(configuration, iconURL: iconURL, bannerURL: bannerURL, work: work)
            return
        }
        if configuration.platform == .arcade {
            try buildArcade(configuration, iconURL: iconURL, bannerURL: bannerURL, work: work)
            return
        }

        let rom = try Data(contentsOf: configuration.romURL)
        let config = try resource("config_block.bin")
        let code = buildCode(rom: rom, config: config, saveOverride: configuration.saveType.value)

        var header = try resource("ncchheader.bin")
        guard let titleID = UInt64(configuration.titleID, radix: 16) else {
            throw ConversionError.invalidResource("Title ID")
        }
        header.writeLE(titleID, at: 0x108)
        header.writeLE(titleID, at: 0x118)
        header.replaceFixed(configuration.productCode.data(using: .ascii)!, at: 0x150, count: 16)
        header[0x18f] |= 0x04

        var exheader = try resource("exheader.bin")
        exheader.replaceFixed(configuration.productCode.dropFirst(6).data(using: .ascii)!, at: 0, count: 8)
        exheader.writeLE(titleID, at: 0x1c8)
        exheader.writeLE(titleID, at: 0x200)

        var icon = try resource("icon.icn")
        patchTitles(&icon, title: configuration.title, longTitle: configuration.longTitle,
                    publisher: configuration.publisher)
        patchIcons(&icon, imageURL: iconURL)
        let banner = try makeBanner(from: bannerURL, in: work)
        let exefs = packExeFS([
            (".code", code),
            ("banner", banner),
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

        if fm.fileExists(atPath: configuration.outputURL.path) {
            try fm.removeItem(at: configuration.outputURL)
        }
        try run("makerom", ["-f", "cia", "-o", configuration.outputURL.path,
                            "-content", "\(cxi.path):0:0", "-ignoresign"])
    }

    private func buildSNES(_ configuration: BuildConfiguration, iconURL: URL,
                           bannerURL: URL, work: URL) throws {
        let fm = FileManager.default
        let romfs = work.appendingPathComponent("romfs")
        try fm.createDirectory(at: romfs, withIntermediateDirectories: true)
        try fm.copyItem(at: configuration.romURL, to: romfs.appendingPathComponent("rom.smc"))
        try Data((configuration.title + "\n").utf8).write(to: romfs.appendingPathComponent("rom.txt"))

        let iconPNG = work.appendingPathComponent("icon.png")
        try normalizedPNG(from: iconURL, width: 48, height: 48, crop: true).write(to: iconPNG)
        let iconBIN = work.appendingPathComponent("icon.bin")
        try run("bannertool", ["makesmdh", "-s", configuration.title,
                                "-l", configuration.longTitle.isEmpty ? configuration.title : configuration.longTitle,
                                "-p", configuration.publisher, "-i", iconPNG.path, "-o", iconBIN.path])

        let bannerBIN = work.appendingPathComponent("banner.bin")
        let bannerPNG = work.appendingPathComponent("banner.png")
        try normalizedPNG(from: bannerURL, width: 256, height: 128, crop: false).write(to: bannerPNG)
        let wavURL = work.appendingPathComponent("banner.wav")
        try silentWAV().write(to: wavURL)
        try run("bannertool", ["makebanner", "-i", bannerPNG.path, "-a", wavURL.path, "-o", bannerBIN.path])

        let uniqueID = String(configuration.titleID.dropFirst(8).dropLast(2))
        if fm.fileExists(atPath: configuration.outputURL.path) { try fm.removeItem(at: configuration.outputURL) }
        try run("makerom", ["-f", "cia", "-target", "t", "-rsf", resources.appendingPathComponent("snes/custom.rsf").path,
                            "-o", configuration.outputURL.path, "-exefslogo", "-icon", iconBIN.path,
                            "-banner", bannerBIN.path, "-elf", resources.appendingPathComponent("snes/snes9x_3ds.elf").path,
                            "-DAPP_TITLE=\(configuration.title)", "-DAPP_PRODUCT_CODE=\(configuration.productCode)",
                            "-DAPP_UNIQUE_ID=0x\(uniqueID)", "-DAPP_ROMFS=\(romfs.path)"])
    }

    private func buildArcade(_ configuration: BuildConfiguration, iconURL: URL,
                             bannerURL: URL, work: URL) throws {
        let fm = FileManager.default
        let runtime = resources.appendingPathComponent("arcade/fba2012_3ds.elf")
        let rsf = work.appendingPathComponent("arcade.rsf")
        guard fm.isReadableFile(atPath: runtime.path) else { throw ConversionError.invalidResource("街机 FBA 核心") }
        let baseRSF = resources.appendingPathComponent("snes/custom.rsf")
        guard let rsfText = try? String(contentsOf: baseRSF, encoding: .utf8) else { throw ConversionError.invalidResource("街机 RSF") }
        let arcadeRSF = rsfText
            .replacingOccurrences(of: "SystemMode                    : 64MB", with: "SystemMode                    : 80MB")
            .replacingOccurrences(of: "SystemModeExt                 : Legacy", with: "SystemModeExt                 : 124MB")
        try arcadeRSF.data(using: .utf8)!.write(to: rsf)

        let romfs = work.appendingPathComponent("romfs")
        let content = romfs.appendingPathComponent("content")
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        try fm.copyItem(at: configuration.romURL, to: content.appendingPathComponent(configuration.romURL.lastPathComponent))

        let iconPNG = work.appendingPathComponent("icon.png")
        try normalizedPNG(from: iconURL, width: 48, height: 48, crop: true).write(to: iconPNG)
        let iconBIN = work.appendingPathComponent("icon.bin")
        try run("bannertool", ["makesmdh", "-s", configuration.title,
                                "-l", configuration.longTitle.isEmpty ? configuration.title : configuration.longTitle,
                                "-p", configuration.publisher, "-i", iconPNG.path, "-o", iconBIN.path])

        let bannerPNG = work.appendingPathComponent("banner.png")
        try normalizedPNG(from: bannerURL, width: 256, height: 128, crop: false).write(to: bannerPNG)
        let bannerBIN = work.appendingPathComponent("banner.bin")
        try silentWAV().write(to: work.appendingPathComponent("banner.wav"))
        try run("bannertool", ["makebanner", "-i", bannerPNG.path, "-a", work.appendingPathComponent("banner.wav").path, "-o", bannerBIN.path])

        let uniqueID = String(configuration.titleID.dropFirst(8).dropLast(2))
        if fm.fileExists(atPath: configuration.outputURL.path) { try fm.removeItem(at: configuration.outputURL) }
        try run("makerom", ["-f", "cia", "-target", "t", "-rsf", rsf.path,
                             "-o", configuration.outputURL.path, "-exefslogo", "-icon", iconBIN.path,
                             "-banner", bannerBIN.path, "-elf", runtime.path,
                             "-DAPP_TITLE=\(configuration.title)", "-DAPP_PRODUCT_CODE=\(configuration.productCode)",
                             "-DAPP_UNIQUE_ID=0x\(uniqueID)", "-DAPP_ROMFS=\(romfs.path)"])
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

    private func buildCode(rom: Data, config: Data, saveOverride: UInt32?) -> Data {
        var cfg = config
        cfg.writeLE(UInt32(rom.count), at: 4)
        cfg.writeLE(saveOverride ?? detectSaveType(in: rom), at: 8)
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

    private func patchTitles(_ icon: inout Data, title: String, longTitle: String, publisher: String) {
        func utf16(_ text: String, bytes: Int) -> Data {
            var data = text.prefix(bytes / 2 - 1).data(using: .utf16LittleEndian)!
            data.append(Data(repeating: 0, count: bytes - data.count))
            return data
        }
        let short = utf16(title, bytes: 0x80)
        let long = utf16(longTitle.isEmpty ? title : longTitle, bytes: 0x100)
        let publisher = utf16(publisher, bytes: 0x80)
        for index in 0..<16 {
            let base = 8 + index * 0x200
            icon.replaceSubrange(base..<(base + 0x80), with: short)
            icon.replaceSubrange((base + 0x80)..<(base + 0x180), with: long)
            icon.replaceSubrange((base + 0x180)..<(base + 0x200), with: publisher)
        }
    }

    private func patchIcons(_ icon: inout Data, imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }
        icon.replaceSubrange(0x2040..<0x24C0, with: swizzledRGB565(image, side: 24))
        icon.replaceSubrange(0x24C0..<0x36C0, with: swizzledRGB565(image, side: 48))
    }

    private func swizzledRGB565(_ image: NSImage, side: Int) -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return Data() }
        let cropSide = min(image.size.width, image.size.height)
        let source = NSRect(x: (image.size.width - cropSide) / 2,
                            y: (image.size.height - cropSide) / 2,
                            width: cropSide, height: cropSide)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: source,
                   operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let morton = [0,1,4,5,16,17,20,21,2,3,6,7,18,19,22,23,8,9,12,13,24,25,28,29,10,11,14,15,26,27,30,31,32,33,36,37,48,49,52,53,34,35,38,39,50,51,54,55,40,41,44,45,56,57,60,61,42,43,46,47,58,59,62,63]
        var output = Data()
        for tileY in 0..<(side / 8) {
            for tileX in 0..<(side / 8) {
                var tile = [UInt16](repeating: 0, count: 64)
                for y in 0..<8 { for x in 0..<8 {
                    let color = bitmap.colorAt(x: tileX * 8 + x, y: tileY * 8 + y) ?? .black
                    let rgb = color.usingColorSpace(.deviceRGB) ?? .black
                    let r = UInt16(rgb.redComponent * 255), g = UInt16(rgb.greenComponent * 255), b = UInt16(rgb.blueComponent * 255)
                    tile[morton[y * 8 + x]] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                }}
                for value in tile { output.appendLE(value) }
            }
        }
        return output
    }

    private func makeBanner(from imageURL: URL, in work: URL) throws -> Data {
        guard let image = NSImage(contentsOf: imageURL) else { throw ConversionError.invalidResource(imageURL.lastPathComponent) }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ConversionError.invalidResource("banner bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 256, height: 128).fill()
        let scale = min(256 / image.size.width, 128 / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: (256 - size.width) / 2, y: (128 - size.height) / 2, width: size.width, height: size.height))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        let pngURL = work.appendingPathComponent("banner.png"), wavURL = work.appendingPathComponent("banner.wav")
        let outputURL = work.appendingPathComponent("banner.bnr")
        try png.write(to: pngURL)
        var wav = Data("RIFF".utf8); wav.appendLE(UInt32(36 + 44100)); wav.append(Data("WAVEfmt ".utf8)); wav.appendLE(UInt32(16)); wav.appendLE(UInt16(1)); wav.appendLE(UInt16(1)); wav.appendLE(UInt32(22050)); wav.appendLE(UInt32(44100)); wav.appendLE(UInt16(2)); wav.appendLE(UInt16(16)); wav.append(Data("data".utf8)); wav.appendLE(UInt32(44100)); wav.append(Data(repeating: 0, count: 44100)); try wav.write(to: wavURL)
        try run("bannertool", ["makebanner", "-i", pngURL.path, "-a", wavURL.path, "-o", outputURL.path])
        return try Data(contentsOf: outputURL)
    }

    private func normalizedPNG(from imageURL: URL, width: Int, height: Int, crop: Bool) throws -> Data {
        guard let image = NSImage(contentsOf: imageURL),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ConversionError.invalidResource(imageURL.lastPathComponent)
        }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let targetRatio = CGFloat(width) / CGFloat(height)
        var source = NSRect(origin: .zero, size: image.size)
        if crop {
            if image.size.width / image.size.height > targetRatio {
                source.size.width = image.size.height * targetRatio; source.origin.x = (image.size.width - source.width) / 2
            } else {
                source.size.height = image.size.width / targetRatio; source.origin.y = (image.size.height - source.height) / 2
            }
        }
        let scale = min(CGFloat(width) / source.width, CGFloat(height) / source.height)
        let drawSize = NSSize(width: source.width * scale, height: source.height * scale)
        image.draw(in: NSRect(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2,
                              width: drawSize.width, height: drawSize.height), from: source,
                   operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func silentWAV() -> Data {
        var wav = Data("RIFF".utf8); wav.appendLE(UInt32(36 + 44100)); wav.append(Data("WAVEfmt ".utf8)); wav.appendLE(UInt32(16)); wav.appendLE(UInt16(1)); wav.appendLE(UInt16(1)); wav.appendLE(UInt32(22050)); wav.appendLE(UInt32(44100)); wav.appendLE(UInt16(2)); wav.appendLE(UInt16(16)); wav.append(Data("data".utf8)); wav.appendLE(UInt32(44100)); wav.append(Data(repeating: 0, count: 44100)); return wav
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
