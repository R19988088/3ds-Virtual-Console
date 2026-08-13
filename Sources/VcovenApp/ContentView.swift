import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var importing = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
            if !model.items.isEmpty {
                Divider()
                List(model.items) { item in
                    itemRow(item)
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Text("\(model.items.count) 个文件")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清除已完成") { model.clearFinished() }
                        .disabled(model.isBuilding)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 580, minHeight: 420)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.add(urls) }
        }
        .onOpenURL { model.add([$0]) }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("拖入 GBA 文件")
                .font(.title2.weight(.semibold))
            Text("支持一次拖入多个文件，CIA 将输出到原文件目录")
                .foregroundStyle(.secondary)
            Button {
                importing = true
            } label: {
                Label("选择文件", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: model.items.isEmpty ? .infinity : 220)
        .padding(28)
        .background(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !BuildIdentity.acceptedROMs(from: urls).isEmpty
        } isTargeted: { targeted = $0 }
    }

    private func itemRow(_ item: BuildItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(item.state))
                .frame(width: 22)
                .foregroundStyle(statusColor(item.state))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.identity.romURL.lastPathComponent)
                    .lineLimit(1)
                Text(statusText(item.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if item.state == .completed {
                Button { model.reveal(item) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
            }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ state: BuildState) -> String {
        switch state {
        case .waiting: "clock"
        case .building: "gearshape.2"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ state: BuildState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        default: .secondary
        }
    }

    private func statusText(_ state: BuildState) -> String {
        switch state {
        case .waiting: "等待转换"
        case .building: "正在生成 CIA…"
        case .completed: "已输出 CIA"
        case .failed(let message): message
        }
    }
}
