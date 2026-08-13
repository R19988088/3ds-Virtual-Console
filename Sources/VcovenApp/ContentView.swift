import SwiftUI
import UniformTypeIdentifiers

private enum ImportKind { case rom, icon, banner }

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var importKind = ImportKind.rom
    @State private var importing = false

    var body: some View {
        HSplitView {
            ScrollView { editor.padding(24) }
                .frame(minWidth: 540, idealWidth: 620)
            ScrollView { preview.padding(24) }
                .frame(minWidth: 390, idealWidth: 460)
        }
        .frame(minWidth: 980, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $importing, allowedContentTypes: importKind == .rom ? [.data] : [.image], allowsMultipleSelection: importKind == .rom) { result in
            guard case .success(let urls) = result else { return }
            handle(urls, as: importKind)
        }
        .onOpenURL { model.add([$0]) }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("vcoven").font(.title.bold())
                    Text("GBA & SNES CIA Builder").foregroundStyle(.secondary)
                }
                Spacer()
                if model.items.count > 1 {
                    Picker("ROM", selection: $model.selection) {
                        ForEach(model.items) { Text($0.romURL.lastPathComponent).tag(Optional($0.id)) }
                    }.frame(width: 220)
                }
            }

            uploadZone(title: "ROM", subtitle: "拖入 .gba / .sfc / .smc 文件", icon: "gamecontroller", url: model.selected?.romURL, kind: .rom)

            HStack(alignment: .top, spacing: 14) {
                uploadZone(title: "图标", subtitle: "48×48 PNG", icon: "photo", url: model.selected?.iconURL, kind: .icon)
                uploadZone(title: "横幅", subtitle: "256×128 PNG", icon: "photo.on.rectangle", url: model.selected?.bannerURL, kind: .banner)
            }

            if model.selected != nil {
                field("标题", text: binding(\.title), hint: "显示在 3DS 主菜单图标下方")
                field("长标题", text: binding(\.longTitle), hint: "选中游戏后显示在下屏")
                field("发布者", text: binding(\.publisher), hint: "显示在下屏标题下方")

                if model.selected?.platform == .gba { VStack(alignment: .leading, spacing: 7) {
                    Text("TITLE ID").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        TextField("000400000F000000", text: binding(\.titleID))
                            .font(.system(.body, design: .monospaced))
                        Button { model.updateSelected { $0.randomizeTitleID() } } label: { Image(systemName: "arrow.clockwise") }
                            .help("生成随机 Title ID")
                    }
                    Text("每个游戏必须唯一，点击刷新按钮可重新生成").font(.caption).foregroundStyle(.tertiary)
                } }
                field("产品码", text: binding(\.productCode), hint: "格式：CTR-N-XXXX", monospaced: true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("存档类型").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("", selection: binding(\.saveType)) {
                        ForEach(SaveType.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { model.buildSelected() } label: {
                    HStack { Spacer(); Label(model.isBuilding ? "正在生成…" : "生成 CIA", systemImage: "shippingbox"); Spacer() }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.isBuilding || model.selected?.validationMessage != nil)

                status
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("3DS 主菜单预览").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.26), Color(red: 0.10, green: 0.10, blue: 0.18)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 10) {
                    image(model.selected?.iconURL, fit: .fill)
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.24), lineWidth: 2))
                    Text(model.selected?.title.isEmpty == false ? model.selected!.title : "Your Game")
                        .foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity).aspectRatio(5 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))

            Text("横幅预览").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                if model.selected?.bannerURL != nil { image(model.selected?.bannerURL, fit: .fit) }
                else { Text("尚未选择横幅").foregroundStyle(.tertiary) }
            }
            .frame(maxWidth: .infinity).aspectRatio(2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            VStack(alignment: .leading, spacing: 9) {
                meta("标题", model.selected?.title ?? "—")
                meta("发布者", model.selected?.publisher ?? "Homebrew")
                meta("Title ID", model.selected?.titleID ?? "—")
                meta("产品码", model.selected?.productCode ?? "—")
                meta("平台", model.selected?.platform.rawValue ?? "—")
                if model.selected?.platform == .gba { meta("存档", model.selected?.saveType.label ?? "自动检测") }
                meta("ROM", model.selected.map { "\($0.romURL.lastPathComponent) (\($0.romSize))" } ?? "—")
            }
            .font(.system(.callout, design: .monospaced)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func uploadZone(title: String, subtitle: String, icon: String, url: URL?, kind: ImportKind) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Button { importKind = kind; importing = true } label: {
                VStack(spacing: 9) {
                    Image(systemName: url == nil ? icon : "checkmark.circle.fill").font(.title2)
                    Text(url?.lastPathComponent ?? subtitle).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, minHeight: kind == .rom ? 92 : 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(url == nil ? Color.secondary.opacity(0.35) : Color.green, style: StrokeStyle(lineWidth: 1.5, dash: url == nil ? [5] : [])))
            .dropDestination(for: URL.self) { urls, _ in handle(urls, as: kind); return true }
        }.frame(maxWidth: .infinity)
    }

    private func field(_ title: String, text: Binding<String>, hint: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("", text: text).font(monospaced ? .system(.body, design: .monospaced) : .body)
            Text(hint).font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var status: some View {
        if let selected = model.selected {
            switch selected.state {
            case .completed:
                HStack { Label("CIA 已生成", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Spacer(); Button("在 Finder 中显示") { model.reveal(selected) } }
            case .failed(let message): Text(message).font(.caption).foregroundStyle(.red)
            case .building: ProgressView().frame(maxWidth: .infinity)
            case .waiting: Text(selected.validationMessage ?? "准备生成").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func image(_ url: URL?, fit: ContentMode) -> some View {
        Group { if let url, let nsImage = NSImage(contentsOf: url) { Image(nsImage: nsImage).resizable().aspectRatio(contentMode: fit) } else { Image(systemName: "questionmark").foregroundStyle(.secondary) } }
    }
    private func meta(_ key: String, _ value: String) -> some View { HStack(alignment: .top) { Text("\(key)：").foregroundStyle(.secondary); Text(value).foregroundStyle(.purple).textSelection(.enabled) } }

    private func binding<T>(_ keyPath: WritableKeyPath<BuildConfiguration, T>) -> Binding<T> {
        Binding(get: { model.selected![keyPath: keyPath] }, set: { value in model.updateSelected { $0[keyPath: keyPath] = value } })
    }

    @discardableResult private func handle(_ urls: [URL], as kind: ImportKind) -> Bool {
        switch kind {
        case .rom: model.add(urls)
        case .icon: if let url = urls.first, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true { model.updateSelected { $0.iconURL = url } }
        case .banner: if let url = urls.first, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true { model.updateSelected { $0.bannerURL = url } }
        }
        return true
    }
}
