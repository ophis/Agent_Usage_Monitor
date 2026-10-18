import AppKit
import Observation
import SwiftUI

// TASK-645: the settings window, FR-3 to FR-9. The host does the reading and writing (main.swift); this is the editor.

@Observable final class SettingsModel {
    var path = ""
    /// FR-9: why the file cannot be shown; editing waits for 用默认值重新开始.
    var error: String?
    var loaded = false
    var threshold = 90.0
    var rows: [AccountRow] = []
    var original = "{}"
    /// A problem with no row (the threshold), or why the save failed.
    var problem: String?
    var status = ""
    var saving = false
    @ObservationIgnored var onSave: () -> Void = {}

    func show(_ file: AccountsFile) {
        path = file.path
        error = file.error
        threshold = file.threshold
        rows = file.accounts
        original = file.original
        loaded = true
    }

    /// FR-9: read-accounts sent the defaults with the error; the file stays as it is until 保存.
    func startOver() { error = nil }

    var request: SaveRequest { SaveRequest(threshold: threshold, accounts: rows, original: original) }

    /// FR-6: each problem on its row; nothing was written.
    func failed(_ problems: [Problem]) {
        for p in problems {
            if let i = p.index, rows.indices.contains(i) { rows[i].problem = p.message } else { problem = p.message }
        }
        status = ""
    }

    func clearProblems() {
        for i in rows.indices { rows[i].problem = nil }
        problem = nil
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(i + offset) else { return }
        rows.swapAt(i, i + offset)
    }

    func remove(_ id: UUID) { rows.removeAll { $0.id == id } }

    func add() { rows.append(AccountRow()) }

    /// FR-3: a folder from Finder, shown with the home as `~`; account dirs such as ~/.claude are hidden folders.
    func choose(_ id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "选择"
        let current = (rows[i].dir as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: current.isEmpty ? NSHomeDirectory() : current)
        guard panel.runModal() == .OK, let url = panel.url, rows.indices.contains(i) else { return }
        rows[i].dir = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置文件：\(model.path)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if !model.loaded {
                ProgressView("正在读取…")
            } else if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("无法读取账号列表", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Text(error).font(.callout).textSelection(.enabled)
                    Text("原文件不会改动。点「用默认值重新开始」后，保存时才会用新的列表替换它。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("用默认值重新开始") { model.startOver() }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                table
                Button { model.add() } label: { Label("添加", systemImage: "plus") }
                HStack(spacing: 8) {
                    Text("提醒阈值 threshold")
                    Stepper(value: $model.threshold, in: 50...100, step: 1) {
                        Text("\(Int(model.threshold))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    Text("用量到这个百分比时提醒，并算作不可用").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                if let problem = model.problem {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text(model.status).foregroundStyle(.secondary)
                }
                Spacer()
                Button("保存") { model.onSave() }
                    .keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.loaded || model.error != nil || model.saving)
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 200, alignment: .topLeading)
        // The content's own height, so the window grows and shrinks with the rows instead of clipping or leaving space.
        .fixedSize(horizontal: false, vertical: true)
        // The system colour, so the view is opaque in light and dark appearance, also when rendered on its own.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("client")
                Text("目录").gridCellColumns(2)
                Text("邮箱（可空）")
                Text("name")
                Color.clear.frame(width: 1, height: 1)
            }
            .font(.callout).foregroundStyle(.secondary)
            ForEach($model.rows) { $row in
                GridRow {
                    Picker("client", selection: $row.client) {
                        Text("claude").tag("claude")
                        Text("codex").tag("codex")
                    }
                    .labelsHidden().frame(width: 96)
                    TextField("~/.claude", text: $row.dir).frame(minWidth: 220)
                    Button("选择…") { model.choose(row.id) }
                    TextField("you@example.com", text: $row.account).frame(minWidth: 180)
                    TextField("name", text: $row.name).frame(minWidth: 110)
                    HStack(spacing: 2) {
                        icon("arrow.up", "上移") { model.move(row.id, by: -1) }.disabled(row.id == model.rows.first?.id)
                        icon("arrow.down", "下移") { model.move(row.id, by: 1) }.disabled(row.id == model.rows.last?.id)
                        icon("minus.circle", "删除") { model.remove(row.id) }
                    }
                }
                if let problem = row.problem {
                    GridRow {
                        Label(problem, systemImage: "exclamationmark.circle.fill")
                            .font(.callout).foregroundStyle(.red).gridCellColumns(6)
                    }
                }
            }
        }
    }

    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless).help(label).accessibilityLabel(label)
    }
}
