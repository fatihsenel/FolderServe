import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings").font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
