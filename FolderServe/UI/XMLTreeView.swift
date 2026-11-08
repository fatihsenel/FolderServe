import SwiftUI
import AppKit

// MARK: - Model

/// One XML element: its name, attributes (in document order) and children.
struct XMLElementNode {
    var name: String
    var attributes: [(name: String, value: String)] = []
    var children: [XMLItem] = []

    /// The text of an element that holds nothing but one piece of text (`<name>Ada</name>`).
    var onlyText: String? {
        if children.count == 1, case .text(let t) = children[0] { return t }
        return nil
    }
}

enum XMLItem {
    case element(XMLElementNode)
    case text(String)
    case comment(String)
}

/// Parses a response body into a tree for `XMLTreeView`. External entities are never resolved.
enum XMLTreeParser {
    static let sizeLimit = 256 * 1024

    /// The root element of an XML body small enough to show as a tree; nil for anything else
    /// (not XML, invalid or cut-off XML), so callers show plain text.
    static func parse(_ data: Data, contentType: String?) -> XMLElementNode? {
        guard data.count <= sizeLimit, looksLikeXML(data, contentType: contentType) else { return nil }
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.stack.count == 1 else { return nil }
        return delegate.root
    }

    static func looksLikeXML(_ data: Data, contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        if type.contains("xml") { return true }
        let head = String(decoding: data.prefix(64), as: UTF8.self).drop(while: \.isWhitespace)
        return head.hasPrefix("<?xml")
    }

    /// Number of elements in the tree (used to decide what starts folded, and in tests).
    static func elementCount(_ node: XMLElementNode) -> Int {
        1 + node.children.reduce(0) { sum, item in
            if case .element(let e) = item { return sum + elementCount(e) } else { return sum }
        }
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XMLElementNode] = []   // stack[0] is a hidden wrapper that ends up holding the root
        var root: XMLElementNode?
        private var text = ""

        override init() {
            super.init()
            stack = [XMLElementNode(name: "")]
        }

        private func flushText() {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            if !t.isEmpty { stack[stack.count - 1].children.append(.text(t)) }
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String]) {
            flushText()
            // XMLParser hands attributes over as a dictionary, so keep them in a stable (sorted) order.
            let attrs = attributeDict.keys.sorted().map { (name: $0, value: attributeDict[$0] ?? "") }
            stack.append(XMLElementNode(name: qName ?? elementName, attributes: attrs))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            flushText()
            guard stack.count > 1 else { return }
            let done = stack.removeLast()
            if stack.count == 1 { root = done } else { stack[stack.count - 1].children.append(.element(done)) }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, foundComment comment: String) {
            flushText()
            if stack.count > 1 { stack[stack.count - 1].children.append(.comment(comment.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
    }
}

// MARK: - Views

/// An XML document shown as a tree: every element that has children has an arrow to fold it.
struct XMLTreeView: View {
    let root: XMLElementNode
    var copyText: String?
    /// Paths ("/users/user[1]") of elements that start folded.
    var folded: Set<String> = []
    @State private var command = JSONFoldCommand(open: true, serial: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button { command = JSONFoldCommand(open: false, serial: command.serial + 1) } label: {
                    Label("Collapse all", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                Button { command = JSONFoldCommand(open: true, serial: command.serial + 1) } label: {
                    Label("Expand all", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Spacer()
                if let copyText {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            XMLElementView(node: root, depth: 0, path: "/" + root.name, folded: folded, command: command)
        }
    }
}

private struct XMLElementView: View {
    let node: XMLElementNode
    let depth: Int
    let path: String
    let folded: Set<String>
    let command: JSONFoldCommand
    @State private var open: Bool

    /// Very large elements start folded so a big document does not flood the panel.
    private static let foldedAbove = 100
    private static let mono = Font.system(size: 12, design: .monospaced)

    init(node: XMLElementNode, depth: Int, path: String, folded: Set<String>, command: JSONFoldCommand) {
        self.node = node
        self.depth = depth
        self.path = path
        self.folded = folded
        self.command = command
        _open = State(initialValue: node.children.count <= Self.foldedAbove && !folded.contains(path))
    }

    var body: some View {
        if node.children.isEmpty {
            line(startTag(selfClosing: true))
        } else if let t = node.onlyText {
            line(startTag(selfClosing: false) + styled(t, nil) + endTag)
        } else {
            container
        }
    }

    private func line(_ text: AttributedString) -> some View {
        Text(text).font(Self.mono).textSelection(.enabled).padding(.leading, 14)
    }

    private var container: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).frame(width: 10)
                    Text(header).font(Self.mono)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(node.children.enumerated()), id: \.offset) { i, item in
                        childView(item, index: i)
                    }
                }
                .padding(.leading, 14)
                Text(endTag).font(Self.mono).padding(.leading, 14)
            }
        }
        // The root always stays open, so "Collapse all" leaves something to see.
        .onChange(of: command) { _, c in if depth > 0 || c.open { open = c.open } }
    }

    @ViewBuilder private func childView(_ item: XMLItem, index: Int) -> some View {
        switch item {
        case .element(let e):
            XMLElementView(node: e, depth: depth + 1, path: path + "/" + e.name + "[\(index)]", folded: folded, command: command)
        case .text(let t):
            line(styled(t, nil))
        case .comment(let c):
            line(styled("<!-- \(c) -->", .secondary))
        }
    }

    private var header: AttributedString {
        var h = startTag(selfClosing: false)
        if !open {
            let n = node.children.count
            h += styled(" … \(n) \(n == 1 ? "item" : "items") ", .secondary) + endTag
        }
        return h
    }

    // MARK: Colouring

    private func styled(_ s: String, _ color: Color?) -> AttributedString {
        var a = AttributedString(s)
        if let color { a.foregroundColor = color }
        return a
    }

    private func startTag(selfClosing: Bool) -> AttributedString {
        var out = styled("<" + node.name, RequestDetailView.jsonKeyColor)
        for attr in node.attributes {
            out += AttributedString(" ")
            out += styled(attr.name, RequestDetailView.jsonNumberColor)
            out += AttributedString("=")
            out += styled("\"" + XMLTreeText.escapeAttribute(attr.value) + "\"", RequestDetailView.jsonStringColor)
        }
        out += styled(selfClosing ? "/>" : ">", RequestDetailView.jsonKeyColor)
        return out
    }

    private var endTag: AttributedString { styled("</" + node.name + ">", RequestDetailView.jsonKeyColor) }
}

enum XMLTreeText {
    /// An attribute value as it would be written inside double quotes.
    static func escapeAttribute(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
