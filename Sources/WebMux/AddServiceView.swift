import SwiftUI

struct AddServiceView: View {
    var store: ServiceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var urlString = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Service").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("URL (e.g. https://slack.com)", text: $urlString)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addService() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || URL(string: urlString) == nil)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func addService() {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") { raw = "https://" + raw }
        guard let url = URL(string: raw) else { return }
        let service = Service(id: UUID(), name: name.trimmingCharacters(in: .whitespaces), url: url)
        store.add(service)
        Task { await FaviconFetcher.fetch(for: service, store: store) }
        dismiss()
    }
}
