import SwiftUI
import FolderServeCore

/// Per-folder fake responses and extra response headers, so a page can be tried without its backend.
struct MocksEditorView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    let entryID: UUID
    @State private var mocks: [MockRule]
    @State private var headers: [HeaderRule]

    init(entryID: UUID, initialMocks: [MockRule], initialHeaders: [HeaderRule]) {
        self.entryID = entryID
        _mocks = State(initialValue: initialMocks)
        _headers = State(initialValue: initialHeaders)
    }

    private static let methods = ["", "GET", "POST", "PUT", "PATCH", "DELETE"]

    var body: some View {
        Group {
            if isSnapshot { content } else { ScrollView { content } }   // ImageRenderer cannot draw ScrollView content
        }
        .frame(width: 560, height: isSnapshot ? nil : 520)
        .onChange(of: mocks) { _, new in manager.setMockRules(entryID, new) }
        .onChange(of: headers) { _, new in manager.setHeaderRules(entryID, new) }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "theatermasks").foregroundStyle(Theme.accent)
                    Text("Mocks and headers").font(.system(size: 15, weight: .semibold, design: .rounded))
                }

                section("Fake responses",
                        "Matching requests get this answer instead of the file or the proxy target. A path is exact (/api/me) or ends in * (/api/*). The first matching rule wins.")
                if mocks.isEmpty { Text("No fake responses yet").font(.callout).foregroundStyle(.secondary) }
                ForEach($mocks) { $rule in mockRow($rule) }
                Button { mocks.append(MockRule()) } label: { Label("Add response", systemImage: "plus") }

                Divider()

                section("Extra headers",
                        "Added to every answer for matching paths: files, proxied calls and fake responses. Use * for all paths.")
                if headers.isEmpty { Text("No extra headers yet").font(.callout).foregroundStyle(.secondary) }
                ForEach($headers) { $rule in headerRow($rule) }
                Button { headers.append(HeaderRule(path: "*", name: "X-Example", value: "1")) } label: { Label("Add header", systemImage: "plus") }
            }
            .padding(16)
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mockRow(_ rule: Binding<MockRule>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: rule.enabled).toggleStyle(.checkbox).labelsHidden().help("Turn this rule on or off")
                methodPicker(rule.method)
                field("/api/me", rule.path)
                field("200", intBinding(rule.status)).frame(width: 52)
                field("0", intBinding(rule.delayMs)).frame(width: 52).help("Delay in milliseconds before answering")
                Text("ms").font(.caption).foregroundStyle(.secondary)
                Button { mocks.removeAll { $0.id == rule.wrappedValue.id } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this rule")
            }
            HStack(spacing: 8) {
                Text("Content type").font(.caption).foregroundStyle(.secondary)
                field("application/json", rule.contentType)
            }
            bodyEditor(rule.body)
            if let problem = rule.wrappedValue.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
    }

    private func headerRow(_ rule: Binding<HeaderRule>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: rule.enabled).toggleStyle(.checkbox).labelsHidden().help("Turn this rule on or off")
                field("*", rule.path).frame(width: 130)
                field("Header-Name", rule.name).frame(width: 150)
                field("value", rule.value)
                Button { headers.removeAll { $0.id == rule.wrappedValue.id } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this header")
            }
            if let problem = rule.wrappedValue.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    // MARK: controls (ImageRenderer cannot draw text fields, so screenshots get drawn boxes)

    @ViewBuilder private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        if isSnapshot {
            Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
        } else {
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
        }
    }

    @ViewBuilder private func methodPicker(_ method: Binding<String>) -> some View {
        if isSnapshot {
            Text(method.wrappedValue.isEmpty ? "Any" : method.wrappedValue).font(.callout)
                .padding(.horizontal, 6).padding(.vertical, 4).frame(width: 78)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
        } else {
            Picker("", selection: method) {
                ForEach(Self.methods, id: \.self) { Text($0.isEmpty ? "Any" : $0).tag($0) }
            }
            .labelsHidden().frame(width: 78)
        }
    }

    @ViewBuilder private func bodyEditor(_ body: Binding<String>) -> some View {
        if isSnapshot {
            Text(body.wrappedValue).font(.system(size: 12, design: .monospaced)).lineLimit(4)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.2)))
        } else {
            TextEditor(text: body).font(.system(size: 12, design: .monospaced))
                .frame(height: 70).scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.2)))
        }
    }

    /// A number field backed by an Int (empty or invalid text becomes 0).
    private func intBinding(_ value: Binding<Int>) -> Binding<String> {
        Binding(get: { String(value.wrappedValue) }, set: { value.wrappedValue = Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 })
    }
}
