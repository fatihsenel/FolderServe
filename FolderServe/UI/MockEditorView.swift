import SwiftUI
import FolderServeCore

/// Edits a folder's mock responses. Changes apply to the running server immediately.
struct MockEditorView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    let entryID: UUID
    @State private var rules: [MockRule]

    init(entryID: UUID, initialRules: [MockRule]) {
        self.entryID = entryID
        _rules = State(initialValue: initialRules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "theatermasks").foregroundStyle(Theme.accent)
                Text("Mock responses").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Text("A request for exactly this path gets the saved answer instead of the folder or the proxy. In Activity, \"Save as mock\" on a request fills one in for you.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if rules.isEmpty {
                Text("No mocks yet").font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            if isSnapshot {
                ruleList
            } else {
                ScrollView { ruleList }.frame(maxHeight: 420)
            }
            HStack {
                Button { rules.append(MockRule(method: "GET", path: "/api/example", body: "{}")) } label: {
                    Label("Add mock", systemImage: "plus")
                }
                Spacer()
            }
            Divider()
            Text("Mocks are saved with this folder's settings on this Mac, up to 256 KB each. The path must match exactly; the query is ignored.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 500)
        .onChange(of: rules) { _, new in manager.setMocks(entryID, new) }
    }

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($rules) { $rule in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $rule.enabled).toggleStyle(.checkbox).labelsHidden().help("Use this mock")
                        methodPicker($rule.method)
                        field("/api/users", $rule.path)
                        Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this mock")
                    }
                    HStack(spacing: 8) {
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                        field("200", Self.statusText($rule.status)).frame(width: 60)
                        Text("Type").font(.caption).foregroundStyle(.secondary)
                        field("application/json", $rule.contentType)
                    }
                    bodyEditor($rule.body)
                    if let problem = rule.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
                    }
                }
                .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
                .opacity(rule.enabled ? 1 : 0.55)
            }
        }
    }

    /// "Any" for an empty method.
    static func methodLabel(_ method: String) -> String { method.isEmpty ? "Any" : method }

    /// The status field edits text; anything that is not a number becomes 0, which the rule reports as a problem.
    static func statusText(_ status: Binding<Int>) -> Binding<String> {
        Binding(get: { status.wrappedValue == 0 ? "" : String(status.wrappedValue) },
                set: { status.wrappedValue = Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 })
    }
}

private extension MockEditorView {
    /// ImageRenderer cannot draw a Menu, a TextField or a TextEditor, so screenshots get drawn boxes with the same text.
    @ViewBuilder func methodPicker(_ method: Binding<String>) -> some View {
        if isSnapshot {
            Text(Self.methodLabel(method.wrappedValue)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1))).frame(width: 84, alignment: .leading)
        } else {
            Picker("", selection: method) {
                ForEach(MockRule.methods, id: \.self) { Text(Self.methodLabel($0)).tag($0) }
            }
            .labelsHidden().frame(width: 84)
        }
    }

    @ViewBuilder func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        if isSnapshot {
            Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
        } else {
            TextField(placeholder, text: text)
        }
    }

    @ViewBuilder func bodyEditor(_ text: Binding<String>) -> some View {
        if isSnapshot {
            Text(text.wrappedValue.isEmpty ? " " : text.wrappedValue).lineLimit(4)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
        } else {
            TextEditor(text: text).font(.system(size: 12, design: .monospaced)).frame(height: 84)
                .scrollContentBackground(.hidden).padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.18)))
                .accessibilityLabel("Response body")
        }
    }
}
