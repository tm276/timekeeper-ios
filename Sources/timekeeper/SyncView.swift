import SwiftUI

struct SyncView: View {

    @State private var store = TimeLogStore()
    @State private var statusText = "Ready to sync"
    @State private var lastSyncText = "No sync yet"
    @State private var availableServicesText = "Checking services..."
    @State private var resultText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                card {
                    Text("Sync")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(statusText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                card {
                    Text("Status")
                        .font(.headline)

                    Text(lastSyncText)
                        .font(.body)

                    Text(availableServicesText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button("Sync Now") {
                    syncNow()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Sync now")

                if !resultText.isEmpty {
                    card {
                        Text("Result")
                            .font(.headline)

                        Text(resultText)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                card {
                    Text("Current iOS behavior")
                        .font(.headline)

                    Text("Sync is manual while the app is open. Nextcloud WebDAV upload is wired. Google Drive is still placeholder.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Sync")
        .onAppear {
            refresh()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func syncNow() {
        store = TimeLogStore()

        let result = SyncOrchestrator.sync(store: store)

        switch result {
        case .success(let message):
            statusText = "Sync completed"
            resultText = message

        case .failure(let error):
            statusText = "Sync failed"
            resultText = error.localizedDescription
        }

        store = TimeLogStore()
        refresh()
    }

    private func refresh() {
        let client = store.getClientById(store.activeClientId) ?? store.clients.first
        let services = SyncOrchestrator.availableServices(for: client)

        if services.isEmpty {
            availableServicesText = "Available services: local CSV only"
        } else {
            availableServicesText = "Available services: " + services.map { $0.rawValue }.joined(separator: ", ")
        }

        if store.lastSyncFailed {
            lastSyncText = "Last sync failed"
        } else if let millis = store.lastSyncMillis {
            lastSyncText = "Last sync: \(TimeFormatUtils.formatDate(millis)) \(TimeFormatUtils.formatTime(millis))"
        } else {
            lastSyncText = "No sync yet"
        }
    }
}
