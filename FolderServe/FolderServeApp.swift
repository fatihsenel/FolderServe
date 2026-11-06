import SwiftUI
import FolderServeCore

@main
struct FolderServeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("FolderServe \(FolderServeCore.version)")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
