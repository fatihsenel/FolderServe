import SwiftUI
import FolderServeCore

/// Edits a folder's API proxy rules. Changes apply to the running server immediately.
struct ProxyEditorView: View {
    @Environment(ServerManager.self) private var manager
    let entryID: UUID
    @State private var rules: [ProxyRule]

    init(entryID: UUID, initialRules: [ProxyRule]) {
        self.entryID = entryID
        _rules = State(initialValue: initialRules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(Theme.accent)
                Text("API proxy").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Text("Requests that start with the prefix are sent to the target, so the browser sees one origin and CORS does not apply. Example: /uiapi → https://localhost:5003")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if rules.isEmpty {
                Text("No rules yet").font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach($rules) { $rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("/api", text: $rule.prefix).frame(width: 110)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("https://localhost:5003", text: $rule.target)
                        Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this rule")
                    }
                    .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Remove prefix when forwarding", isOn: $rule.stripPrefix)
                            .toggleStyle(.checkbox).font(.caption)
                        Toggle("Point this address at FolderServe in served files", isOn: $rule.rewriteAddress)
                            .toggleStyle(.checkbox).font(.caption)
                            .help("Replaces the target address (e.g. https://localhost:5003) in config.json, JS and HTML files when they are served, so an app with a hard-coded API address calls the proxy and avoids CORS. Your files are not changed.")
                    }
                    HStack {
                        if let problem = rule.problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
            }

            HStack {
                Button { rules.append(ProxyRule(prefix: "/api", target: "http://localhost:3000")) } label: {
                    Label("Add rule", systemImage: "plus")
                }
                Spacer()
            }
            Divider()
            Text("Self-signed certificates are accepted for localhost targets only. Requests from other origins are blocked unless CORS is on for this folder.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 460)
        .onChange(of: rules) { _, new in manager.setProxyRules(entryID, new) }
    }
}
