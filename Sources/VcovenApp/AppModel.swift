import AppKit
import Foundation

enum BuildState: Equatable {
    case waiting, building, completed, failed(String)
}

struct BuildItem: Identifiable {
    let id = UUID()
    let identity: BuildIdentity
    var state: BuildState = .waiting
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [BuildItem] = []
    @Published var isBuilding = false

    func add(_ urls: [URL]) {
        let existing = Set(items.map { $0.identity.romURL.standardizedFileURL.path })
        items += BuildIdentity.acceptedROMs(from: urls)
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .map { BuildItem(identity: BuildIdentity(for: $0)) }
        buildPending()
    }

    func buildPending() {
        guard !isBuilding, items.contains(where: { $0.state == .waiting }) else { return }
        isBuilding = true
        Task {
            for index in items.indices where items[index].state == .waiting {
                items[index].state = .building
                let identity = items[index].identity
                do {
                    try await Task.detached { try VcovenConverter().build(identity) }.value
                    items[index].state = .completed
                } catch {
                    items[index].state = .failed(error.localizedDescription)
                }
            }
            isBuilding = false
        }
    }

    func reveal(_ item: BuildItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.identity.outputURL])
    }

    func clearFinished() {
        items.removeAll { if case .building = $0.state { return false }; return $0.state != .waiting }
    }
}
