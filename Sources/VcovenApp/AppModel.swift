import AppKit
import Foundation

enum BuildState: Equatable, Sendable {
    case waiting, building, completed, failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [BuildConfiguration] = []
    @Published var selection: UUID?
    @Published var isBuilding = false

    func add(_ urls: [URL]) {
        let existing = Set(items.map { $0.romURL.standardizedFileURL.path })
        let added = BuildIdentity.acceptedROMs(from: urls)
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .map(BuildConfiguration.init)
        items += added
        if selection == nil { selection = added.first?.id }
    }

    var selectedIndex: Int? { items.firstIndex { $0.id == selection } }
    var selected: BuildConfiguration? { selectedIndex.map { items[$0] } }

    func updateSelected(_ update: (inout BuildConfiguration) -> Void) {
        guard let index = selectedIndex else { return }
        update(&items[index])
    }

    func buildSelected() {
        guard !isBuilding, let index = selectedIndex, items[index].validationMessage == nil else { return }
        isBuilding = true
        Task {
            items[index].state = .building
            let configuration = items[index]
            do {
                try await Task.detached { try VcovenConverter().build(configuration) }.value
                items[index].state = .completed
            } catch {
                items[index].state = .failed(error.localizedDescription)
            }
            isBuilding = false
        }
    }

    func reveal(_ item: BuildConfiguration) {
        NSWorkspace.shared.activateFileViewerSelecting([item.outputURL])
    }

    func clearFinished() {
        items.removeAll { if case .building = $0.state { return false }; return $0.state == .completed }
        if !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
    }
}
