import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import FolderServeCore

/// QR code and addresses for opening a shared folder from a phone on the same network.
struct SharePopoverView: View {
    @Environment(ServerManager.self) private var manager
    let entryID: UUID
    @State private var selected = 0

    private var urls: [URL] { manager.lanURLs(for: entryID) }

    var body: some View {
        VStack(spacing: 12) {
            if urls.isEmpty {
                Label("No network address found. Connect to Wi-Fi or Ethernet.", systemImage: "wifi.slash")
                    .font(.callout).foregroundStyle(.secondary).frame(width: 240)
            } else {
                let url = urls[min(selected, urls.count - 1)]
                if let image = QRCode.image(for: url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable()
                        .frame(width: 180, height: 180)
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(.white))
                        .accessibilityLabel("QR code for \(url.absoluteString)")
                }
                Text("Scan with your phone's camera").font(.callout).foregroundStyle(.secondary)
                if urls.count > 1 {
                    Picker("Address", selection: $selected) {
                        ForEach(urls.indices, id: \.self) { Text(urls[$0].host ?? "").tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
                }
                HStack(spacing: 8) {
                    Text(url.absoluteString).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy address")
                }
                Text("Anyone on this network can open it while sharing is on. The first time, macOS may ask to allow incoming connections.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 240)
            }
        }
        .padding(16)
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
