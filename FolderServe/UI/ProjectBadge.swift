import SwiftUI
import FolderServeCore

extension ProjectKind {
    /// Brand colour for the framework mark.
    var brandColor: Color {
        switch self {
        case .angular: Color(red: 0.867, green: 0.0, blue: 0.188)
        case .react: Color(red: 0.38, green: 0.855, blue: 0.984)
        case .vue: Color(red: 0.255, green: 0.722, blue: 0.514)
        case .svelte: Color(red: 1.0, green: 0.243, blue: 0.0)
        case .next: Color.primary
        case .nuxt: Color(red: 0.0, green: 0.863, blue: 0.51)
        case .astro: Color(red: 0.737, green: 0.4, blue: 1.0)
        case .vite: Color(red: 0.74, green: 0.51, blue: 1.0)
        case .html: Color(red: 0.89, green: 0.302, blue: 0.149)
        }
    }

    var imageName: String { "Frameworks/\(rawValue)" }
}

/// Small framework logo, optionally with its name.
struct ProjectBadge: View {
    let kind: ProjectKind
    var showsName = true

    var body: some View {
        HStack(spacing: 5) {
            Image(kind.imageName).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 12, height: 12).foregroundStyle(kind.brandColor)
            if showsName { Text(kind.displayName).font(.caption2.weight(.medium)) }
        }
        .padding(.horizontal, showsName ? 8 : 5).padding(.vertical, 3)
        .background(Capsule().fill(kind.brandColor.opacity(0.14)))
        .overlay(Capsule().strokeBorder(kind.brandColor.opacity(0.35), lineWidth: 0.5))
        .help("\(kind.displayName) project")
        .accessibilityLabel("\(kind.displayName) project")
    }
}
