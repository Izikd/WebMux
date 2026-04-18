import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("WebMux").font(.title).fontWeight(.semibold)

            Text("Version \(BuildInfo.version)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Built \(BuildInfo.buildDate)")
                .font(.caption).foregroundStyle(.tertiary)

            Divider().padding(.horizontal, 40)

            Text("All your web apps in one native macOS window.")
                .font(.callout)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                infoRow("Engine", "System WebKit (WKWebView)")
                infoRow("Runtime", "Swift \(swiftVersion) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                infoRow("License", "MIT")
            }
            .font(.caption)
            .padding(.horizontal, 20)

            Link("GitHub Repository", destination: URL(string: "https://github.com/Izikd/WebMux")!)
                .font(.caption)

            Spacer().frame(height: 4)

            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 300)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            Text(value)
        }
    }

    private var swiftVersion: String {
        #if swift(>=6.0)
        "6"
        #elseif swift(>=5.0)
        "5"
        #else
        "?"
        #endif
    }
}
