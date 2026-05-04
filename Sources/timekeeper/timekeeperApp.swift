import SwiftUI

@main
struct timekeeperApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @State private var store = TimeLogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        autoSyncIfEnabled()
                    }
                }
        }
    }

    private func autoSyncIfEnabled() {
        guard let client = store.clients.first(where: { $0.autoSyncEnabled }) ?? store.clients.first else {
            return
        }
        guard client.autoSyncEnabled else { return }
        Task.detached(priority: .background) {
            _ = SyncOrchestrator.sync(store: TimeLogStore())
        }
    }
}
