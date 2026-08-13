import CryptoKit
import Foundation

struct BuildIdentity: Sendable {
    let romURL: URL
    let title: String
    let outputURL: URL
    let titleID: String
    let productCode: String

    init(for romURL: URL) {
        self.romURL = romURL
        title = romURL.deletingPathExtension().lastPathComponent
        outputURL = romURL.deletingPathExtension().appendingPathExtension("cia")

        let digest = SHA256.hash(data: Data(romURL.standardizedFileURL.path.utf8))
        let suffix = digest.prefix(2).map { String(format: "%02X", $0) }.joined()
        titleID = "000400000F" + suffix + "00"
        productCode = "CTR-N-" + digest.prefix(2).map { String(format: "%02X", $0) }.joined()
    }

    static func acceptedROMs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            guard ["gba", "sfc", "smc", "zip"].contains(url.pathExtension.lowercased()) else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
