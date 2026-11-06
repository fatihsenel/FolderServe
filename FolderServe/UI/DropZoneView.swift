import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool
    let addFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(isTargeted ? 0.45 : 0.22)).frame(width: 120, height: 120).blur(radius: 18)
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "folder.badge.plus")
                    .font(.system(size: 54, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            Text(isTargeted ? "Drop to start serving" : "Drop a folder here")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("It will be served at http://127.0.0.1 with live reload.")
                .foregroundStyle(.secondary)
            Button("Choose Folder…", action: addFolder)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.7 : 0.25))
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
