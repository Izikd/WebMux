import SwiftUI

@MainActor @Observable
final class GeneralSettings {
    static let shared = GeneralSettings()

    private static let preloadKey = "preloadServices"

    /// Load every service in the background at launch, one at a time. Defaults to on.
    var preloadServices: Bool {
        didSet { UserDefaults.standard.set(preloadServices, forKey: Self.preloadKey) }
    }

    private init() {
        preloadServices = UserDefaults.standard.object(forKey: Self.preloadKey) as? Bool ?? true
    }
}

@MainActor @Observable
final class FontSettings {
    static let shared = FontSettings()

    var enabled: Bool {
        didSet { save() }
    }
    var fontFamily: String {
        didSet { save() }
    }
    var fontSize: Int {
        didSet { save() }
    }

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "fontEnabled")
        fontFamily = d.string(forKey: "fontFamily") ?? ""
        fontSize = d.integer(forKey: "fontSize")
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: "fontEnabled")
        d.set(fontFamily, forKey: "fontFamily")
        d.set(fontSize, forKey: "fontSize")
    }

    static var availableFonts: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }
}

struct SettingsView: View {
    @Bindable var fontSettings = FontSettings.shared
    @Bindable var generalSettings = GeneralSettings.shared
    var webViewManager: WebViewManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredFonts: [String] {
        if searchText.isEmpty { return FontSettings.availableFonts }
        return FontSettings.availableFonts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Preload all services at launch", isOn: $generalSettings.preloadServices)
                Text("Services load in the background one at a time, starting with the selected one. Takes effect on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Font Settings").font(.headline)

            Toggle("Override fonts", isOn: $fontSettings.enabled)

            if fontSettings.enabled {
                TextField("Search fonts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                List(filteredFonts, id: \.self, selection: $fontSettings.fontFamily) { font in
                    HStack {
                        Text(font)
                            .font(.custom(font, size: 14))
                        Spacer()
                        if font == fontSettings.fontFamily {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { fontSettings.fontFamily = font }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Size override:")
                    Picker("", selection: $fontSettings.fontSize) {
                        Text("Default").tag(0)
                        ForEach([12, 13, 14, 15, 16, 18, 20], id: \.self) { size in
                            Text("\(size)px").tag(size)
                        }
                    }
                    .frame(width: 120)
                }

                if !fontSettings.fontFamily.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:").font(.caption).foregroundStyle(.secondary)
                        Text("The quick brown fox — שועל חום מהיר")
                            .font(.custom(fontSettings.fontFamily, size: CGFloat(fontSettings.fontSize > 0 ? fontSettings.fontSize : 14)))
                            .padding(8)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Divider()

            HStack {
                Button("Apply") {
                    webViewManager.applyFontToAll()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
