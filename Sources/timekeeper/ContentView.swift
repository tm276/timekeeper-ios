import SwiftUI
import CoreLocation


struct ContentView: View, @unchecked Sendable {

    @Environment(\.scenePhase) private var scenePhase

    @State private var store = TimeLogStore()
    @State private var newClientName = ""
    @State private var editingClientId = ""
    @State private var editingClientName = ""
    @State private var statusText = "Ready"
    @State private var currentSiteMatches: [LocationMatcher.Match] = []
    @State private var clientToDelete: ClientProfile? = nil
    @State private var showDeleteClientConfirm = false
    private let mainLocationProvider = CurrentLocationProvider()

    private let appBackground = Color(red: 0.07, green: 0.07, blue: 0.07)
private let siteCardBackground = Color(red: 0.19, green: 0.27, blue: 0.23)
private let siteAccent = Color(red: 0.65, green: 0.84, blue: 0.66)
    private let panelBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    private let cardBackground = Color(red: 0.15, green: 0.20, blue: 0.22)
    private let primaryAction = Color(red: 0.39, green: 0.71, blue: 0.96)
    private let secondaryAction = Color(red: 0.22, green: 0.28, blue: 0.31)
    private let destructiveAction = Color(red: 0.90, green: 0.45, blue: 0.45)
    private let primaryText = Color(red: 0.96, green: 0.96, blue: 0.96)
    private let secondaryText = Color(red: 0.81, green: 0.85, blue: 0.86)

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                VStack(spacing: 12) {
                    Text("TimeKeeper")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)
                        .padding(.top, 12)

                    makeClientPanel

                    if store.clients.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(store.clients, id: \.id) { client in
                                    clientCard(client)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .navigationBarHidden(true)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onAppear {
                reloadStore()
                Task { await refreshCurrentSite() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    reloadStore()
                    Task { await refreshCurrentSite() }
                }
            }
            .alert("Delete \(clientToDelete?.clientName ?? "client")?", isPresented: $showDeleteClientConfirm) {
                Button("Delete", role: .destructive) {
                    if let client = clientToDelete {
                        deleteClient(client)
                    }
                    clientToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    clientToDelete = nil
                }
            } message: {
                Text("This will permanently delete the client and all their time entries.")
            }
        }
    }

    private var makeClientPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clients")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(primaryText)

            TextField("Client Name", text: $newClientName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Client Name")

            Button {
                makeClient()
            } label: {
                Text("Make Client")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
            }
            .background(primaryAction)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Make Client")

            Text(statusText)
                .font(.caption)
                .foregroundStyle(secondaryText)
        }
        .padding()
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No clients yet")
                .foregroundStyle(secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func clientCard(_ client: ClientProfile) -> some View {
        let siteMatch = currentSiteMatches.first { $0.workSite.clientId == client.id }
        let isAtSite = siteMatch != nil
        let siteName = siteMatch?.workSite.siteName
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                ClientDashboardView(clientId: client.id)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(client.clientName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)

                    if let siteName {
                        Text("At site: \(siteName)")
                            .fontWeight(.bold)
                            .foregroundStyle(siteAccent)
                    }

                    if !client.userName.isEmpty {
                        Text("User: \(client.userName)")
                            .foregroundStyle(secondaryText)
                    }

                    Text("Tap card to open client")
                        .foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Open client \(client.clientName)\(siteName.map { ", at site \($0)" } ?? "")")
            .buttonStyle(.plain)

            if editingClientId == client.id {
                TextField("Client Name", text: $editingClientName)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Save") {
                        saveClientName(client)
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(primaryAction)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Save client name")
                    Button("Cancel") {
                        editingClientId = ""
                        editingClientName = ""
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(secondaryAction)
                    .foregroundStyle(primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Cancel editing")
                }
            } else {
                HStack(spacing: 8) {
                    Button("Edit Name") {
                        editingClientId = client.id
                        editingClientName = client.clientName
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(secondaryAction)
                    .foregroundStyle(primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Edit client name")
                    Button("Delete") {
                        clientToDelete = client
                        showDeleteClientConfirm = true
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(destructiveAction)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .accessibilityLabel("Delete client \(client.clientName)")
                }
            }
        }
        .padding()
        .background(isAtSite ? siteCardBackground : cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func makeClient() {
        let trimmed = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            statusText = "Client name required"
            return
        }

        store.addClient(clientName: trimmed)
        newClientName = ""
        statusText = "Client created"
        reloadStore()
    }

    private func saveClientName(_ client: ClientProfile) {
        let trimmed = editingClientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            statusText = "Client name required"
            return
        }

        let updated = ClientProfile(
            id: client.id,
            clientName: trimmed,
            userName: client.userName,
            csvFileName: client.csvFileName,
            localFolder: client.localFolder,
            googleDriveAccount: client.googleDriveAccount,
            googleDriveFolder: client.googleDriveFolder,
            nextcloudUrl: client.nextcloudUrl,
            nextcloudUser: client.nextcloudUser,
            nextcloudPassword: client.nextcloudPassword,
            nextcloudFolder: client.nextcloudFolder,
            autoSyncEnabled: client.autoSyncEnabled,
            syncGoogleDriveEnabled: client.syncGoogleDriveEnabled,
            syncNextcloudEnabled: client.syncNextcloudEnabled
        )

        store.updateClient(updated)
        editingClientId = ""
        editingClientName = ""
        statusText = "Client name saved"
        reloadStore()
    }

    private func deleteClient(_ client: ClientProfile) {
        store.deleteClient(clientId: client.id)
        statusText = "Deleted \(client.clientName)"
        reloadStore()
    }

    private func reloadStore() {
        store = TimeLogStore()
        Task { await refreshCurrentSite() }
    }

    private func refreshCurrentSite() async {
        let location = await mainLocationProvider.getCurrentLocation()
        guard let location else { return }
        let sites = WorkSiteStore().loadSites()
        currentSiteMatches = LocationMatcher.findCurrentSites(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            workSites: sites
        )
    }



}
struct WrongSiteWarning: Identifiable {
    let id = UUID()
    let siteName: String
    let clientName: String
    let clientId: String
    let matches: [(id: String, name: String, siteName: String)]
}

struct ClientDashboardView: View {

    let clientId: String

    @State private var store = TimeLogStore()
    @State private var statusText = "Ready"
    @State private var activeStatus = "Ready to start"
    @State private var lastEntryText = "No entries yet"
    @State private var description = ""
    @State private var dialogMode = "Stop"
    @State private var showDescriptionDialog = false
    @State private var showEditDescriptionDialog = false
    @State private var isSyncing = false
    @State private var syncStatusText = ""
    @State private var wrongSiteWarning: WrongSiteWarning? = nil
    @State private var navigateToWarningClient = false
    @State private var warningClientId = ""
    private let locationProvider = CurrentLocationProvider()
    @State private var editDescription = ""
    @State private var editStartMillis: Int64 = 0
    @State private var editStopMillis: Int64 = 0

    private let panelBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
    private let cardBackground = Color(red: 0.15, green: 0.20, blue: 0.22)
    private let primaryAction = Color(red: 0.39, green: 0.71, blue: 0.96)
    private let secondaryAction = Color(red: 0.22, green: 0.28, blue: 0.31)
    private let destructiveAction = Color(red: 0.90, green: 0.45, blue: 0.45)
    private let primaryText = Color(red: 0.96, green: 0.96, blue: 0.96)
    private let secondaryText = Color(red: 0.81, green: 0.85, blue: 0.86)

    private var client: ClientProfile? {
        store.getClientById(clientId)
    }

    private var entries: [TimeEntry] {
        store.getEntriesForClient(clientId: clientId).sorted { $0.startMillis > $1.startMillis }
    }

    private var isRunning: Bool {
        store.activeClientId == clientId
    }

    private var windowInfo: CsvWindowManager.Window {
        CsvWindowManager.windowFor(
            Int64(Date().timeIntervalSince1970 * 1000),
            settings: store.settings
        )
    }

    private var safeClientName: String {
        let name = client?.clientName ?? "client"
        let replaced = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return replaced.isEmpty ? "client" : replaced
    }

    private var currentCsvFileName: String {
        "timelog_\(safeClientName)_\(windowInfo.key).csv"
    }

    private var currentWindowEntries: [TimeEntry] {
        entries.filter {
            $0.stopMillis >= windowInfo.startMillis &&
            $0.stopMillis < windowInfo.endMillis
        }
    }

    private var currentWindowTotalMinutes: Int64 {
        currentWindowEntries.reduce(Int64(0)) { $0 + $1.durationMinutes }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                card {
                    Text(client?.clientName ?? "Client")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)

                    Text(statusText)
                        .foregroundStyle(secondaryText)
                }

                HStack(spacing: 8) {
                    NavigationLink {
                        SettingsView(clientId: clientId)
                    } label: {
                        Text("Settings")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(secondaryAction)
                            .foregroundStyle(primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityLabel("Open settings for this client")
                }

                card {
                    Text("Current Week")
                        .foregroundStyle(secondaryText)

                    Text("\(TimeFormatUtils.formatDate(windowInfo.startMillis)) → \(TimeFormatUtils.formatDate(windowInfo.endMillis - 1))")
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)

                    Text("CSV File")
                        .foregroundStyle(secondaryText)

                    Text(currentCsvFileName)
                        .foregroundStyle(primaryText)
                }

                card {
                    Text("Last Sync")
                        .foregroundStyle(secondaryText)

                    Text(formatLastSync())
                        .fontWeight(.bold)
                        .foregroundStyle(store.lastSyncFailed ? destructiveAction : primaryText)
                }

                card {
                    Text(isRunning ? "Session in progress" : "Ready to start")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)

                    Text(activeStatus)
                        .foregroundStyle(secondaryText)

                    if isRunning {
                        HStack(spacing: 8) {
                            Button {
                                description = ""
                                dialogMode = "Stop"
                                showDescriptionDialog = true
                            } label: {
                                Text("Stop")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Rectangle())
                            }
                            .background(destructiveAction)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Button {
                                description = ""
                                dialogMode = "Next Task"
                                showDescriptionDialog = true
                            } label: {
                                Text("Next Task")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Rectangle())
                            }
                            .background(primaryAction)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        Button {
                            Task { await checkLocationBeforeStart() }
                        } label: {
                            Text("Start")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .contentShape(Rectangle())
                        }
                        .background(primaryAction)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                if showDescriptionDialog {
                    descriptionPanel
                }

                card {
                    Text("This Week Total")
                        .foregroundStyle(secondaryText)

                    Text("\(currentWindowTotalMinutes) min")
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)
                }

                card {
                    Text("Recent Entries")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(primaryText)

                    if entries.isEmpty {
                        Text("No time entries yet")
                            .foregroundStyle(secondaryText)
                    } else {
                        ForEach(entries.prefix(10)) { entry in
                            recentEntryCard(entry)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        .sheet(item: $wrongSiteWarning) { warning in
            VStack(alignment: .leading, spacing: 16) {
                Text("Wrong Client Site?")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(primaryText)

                Text("You appear to be at \(warning.siteName). The following clients are registered at this location:")
                    .foregroundStyle(secondaryText)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(warning.matches, id: \.id) { match in
                        Button {
                            warningClientId = match.id
                            wrongSiteWarning = nil
                            navigateToWarningClient = true
                        } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.name)
                                        .fontWeight(.bold)
                                        .foregroundStyle(primaryText)
                                    Text("Site: \(match.siteName)")
                                        .foregroundStyle(secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                    }
                }
                }

                Button("Start Anyway for \(store.getClientById(clientId)?.clientName ?? "this client")") {
                    wrongSiteWarning = nil
                    startTimer()
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primaryAction)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())

                Button("Cancel") {
                    wrongSiteWarning = nil
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(secondaryAction)
                .foregroundStyle(primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
            }
            .padding()
            .background(panelBackground)
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $navigateToWarningClient) {
            ClientDashboardView(clientId: warningClientId)
        }
        .sheet(isPresented: $showEditDescriptionDialog) {
            VStack(spacing: 16) {
                Text("Edit Description")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(primaryText)
                TextField("What did you work on", text: $editDescription, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let _ = store.updateEntryDescription(
                        clientId: clientId,
                        startMillis: editStartMillis,
                        stopMillis: editStopMillis,
                        description: editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    showEditDescriptionDialog = false
                    editDescription = ""
                    refresh()
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(primaryAction)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Button("Cancel") {
                    showEditDescriptionDialog = false
                    editDescription = ""
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(secondaryAction)
                .foregroundStyle(primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
            .presentationDetents([.medium])
        }
        .navigationTitle(client?.clientName ?? "Client")
        .onAppear {
            refresh()
        }
    }

    private var descriptionPanel: some View {
        card {
            Text(dialogMode == "Stop" ? "Stop Timer" : "Next Task")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(primaryText)

            TextField("What did you work on", text: $description, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("What did you work on")

            Button {
                confirmDescription()
            } label: {
                Text(dialogMode == "Stop" ? "Stop" : "Save and Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .background(primaryAction)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                description = ""
                showDescriptionDialog = false
            } label: {
                Text("Cancel")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .background(secondaryAction)
            .foregroundStyle(primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func recentEntryCard(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.description.isEmpty ? "No description" : entry.description)
                .fontWeight(.bold)
                .foregroundStyle(primaryText)

            Text("\(TimeFormatUtils.formatTime(entry.startMillis)) - \(TimeFormatUtils.formatTime(entry.stopMillis))")
                .foregroundStyle(secondaryText)

            Text("\(entry.durationMinutes) min")
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            editDescription = entry.description
            editStartMillis = entry.startMillis
            editStopMillis = entry.stopMillis
            showEditDescriptionDialog = true
        }
        .accessibilityElement(children: .contain)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func checkLocationBeforeStart() async {
        let allSitesDebug = WorkSiteStore().loadSites()
        print("[DEBUG] All sites count: \(allSitesDebug.count)")
        for s in allSitesDebug { print("[DEBUG] site: \(s.siteName) clientId: \(s.clientId)") }
        print("[DEBUG] current clientId: \(clientId)")
        let location = await locationProvider.getCurrentLocation()

        if let location {
            let allSites = WorkSiteStore().loadSites()
            let matches = LocationMatcher.findCurrentSites(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                workSites: allSites
            )

            print("[Location] total matches: \(matches.count)")
            for m in matches { print("[Location] match: \(m.workSite.clientId) site: \(m.workSite.siteName)") }
            let wrongMatches = Array(matches.filter { $0.workSite.clientId != clientId }.prefix(3))
            print("[Location] wrong matches: \(wrongMatches.count)")

            let currentClientMatches = matches.filter { $0.workSite.clientId == clientId }
            if !wrongMatches.isEmpty && currentClientMatches.isEmpty {
                let first = wrongMatches[0]
                let matched: [(id: String, name: String, siteName: String)] = wrongMatches.map { match in
                    (
                        id: match.workSite.clientId,
                        name: store.getClientById(match.workSite.clientId)?.clientName ?? "Unknown",
                        siteName: match.workSite.siteName
                    )
                }
                wrongSiteWarning = WrongSiteWarning(
                    siteName: first.workSite.siteName,
                    clientName: store.getClientById(first.workSite.clientId)?.clientName ?? "another client",
                    clientId: first.workSite.clientId,
                    matches: matched
                )
                return
            }
        }

        startTimer()
    }

    private func startTimer() {
        store.startTimer(clientId: clientId)
        statusText = "Timer started"
        refresh()
    }

    private func confirmDescription() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let continueAfterStop = dialogMode == "Next Task"

        store.stopTimer(description: trimmed)

        if continueAfterStop {
            store.startTimer(clientId: clientId)
            statusText = "Saved and started next task"
        } else {
            statusText = "Timer stopped"
        }

        description = ""
        showDescriptionDialog = false
        refresh()
    }

    private func formatLastSync() -> String {
        if store.lastSyncFailed {
            return "Sync: failed"
        }

        guard let millis = store.lastSyncMillis else {
            return "Last Sync: never"
        }

        return "Last Sync: \(TimeFormatUtils.formatDate(millis)) at \(TimeFormatUtils.formatTime(millis))"
    }


    private func runSync() {
        isSyncing = true
        syncStatusText = "Syncing..."
        let result = SyncOrchestrator.sync(store: store)
        switch result {
        case .success(let message):
            syncStatusText = message
        case .failure(let error):
            syncStatusText = error.localizedDescription
        }
        store = TimeLogStore()
        isSyncing = false
        refresh()
    }

    private func refresh() {
        store = TimeLogStore()

        if isRunning, let start = store.activeStartMillis {
            activeStatus = "Started at: \(TimeFormatUtils.formatTime(start)) on \(TimeFormatUtils.formatDate(start))"
        } else {
            activeStatus = "Use Start to begin tracking time for this client."
        }

        if let last = entries.first {
            lastEntryText = "\(last.description.isEmpty ? "No description" : last.description)\n\(TimeFormatUtils.formatTime(last.startMillis)) - \(TimeFormatUtils.formatTime(last.stopMillis))\n\(last.durationMinutes) min"
        } else {
            lastEntryText = "No time entries yet"
        }
    }
}


struct CsvHistoryEntry: Identifiable {
    let id = UUID()
    let date: String
    let startTime: String
    let stopTime: String
    let durationMinutes: String
    let description: String
}

struct HistoryView: View {

    let store: TimeLogStore
    let selectedClientId: String

    @State private var csvFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var selectedEntries: [CsvHistoryEntry] = []

    private let historyBackground = Color(red: 0.07, green: 0.07, blue: 0.07)
    private let historyPanel = Color(red: 0.12, green: 0.12, blue: 0.12)
    private let historyCard = Color(red: 0.15, green: 0.20, blue: 0.22)
    private let historyPrimary = Color(red: 0.39, green: 0.71, blue: 0.96)
    private let historyText = Color.white
    private let historySecondaryText = Color(red: 0.81, green: 0.85, blue: 0.86)

    var body: some View {
        VStack(spacing: 12) {
            Text("Timecard History")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(historyText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            availableTimecardsPanel

            selectedTimecardPanel
        }
        .padding(12)
        .background(historyBackground)
        .navigationTitle("History")
        .onAppear {
            loadCsvFiles()
        }
    }

    private var availableTimecardsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available timecards")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(historyText)
                .accessibilityAddTraits(.isHeader)

            if csvFiles.isEmpty {
                Text("No saved CSV files found yet.")
                    .foregroundStyle(historySecondaryText)
            } else {
                ForEach(csvFiles, id: \.path) { file in
                    timecardFileRow(file)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(historyPanel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var selectedTimecardPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if selectedFile == nil {
                    Text("Select a timecard to view it.")
                        .foregroundStyle(historySecondaryText)
                } else if selectedEntries.isEmpty {
                    Text("No entries found in \(selectedFile?.lastPathComponent ?? "selected file").")
                        .foregroundStyle(historySecondaryText)
                } else {
                    Text(selectedFile?.lastPathComponent ?? "")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(historyText)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(selectedEntries) { entry in
                        historyEntryCard(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(historyPanel)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func timecardFileRow(_ file: URL) -> some View {
        let isSelected = selectedFile?.path == file.path
        let visibleLabel = isSelected ? "Selected: \(file.lastPathComponent)" : file.lastPathComponent

        return Button {
            selectedFile = file
            selectedEntries = parseCsvHistory(file)
        } label: {
            Text(visibleLabel)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(historyText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding()
                .background(isSelected ? historyPrimary.opacity(0.25) : historyCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel(isSelected ? "Selected timecard \(file.lastPathComponent)" : "Open timecard \(file.lastPathComponent)")
    }

    private func historyEntryCard(_ entry: CsvHistoryEntry) -> some View {
        let description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No description"
            : entry.description

        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.date)
                .fontWeight(.bold)
                .foregroundStyle(historyText)

            Text("Start: \(entry.startTime)")
                .foregroundStyle(historySecondaryText)

            Text("Stop: \(entry.stopTime)")
                .foregroundStyle(historySecondaryText)

            Text("Duration: \(entry.durationMinutes) minutes")
                .foregroundStyle(historySecondaryText)

            Text("Description: \(description)")
                .foregroundStyle(historySecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(historyCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time entry. Date \(entry.date). Start \(entry.startTime). Stop \(entry.stopTime). Duration \(entry.durationMinutes) minutes. Description: \(description).")
    }

    private func loadCsvFiles() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let files = FileManager.default.enumerator(
            at: documents,
            includingPropertiesForKeys: nil
        )?
        .compactMap { $0 as? URL }
        .filter {
            $0.lastPathComponent.hasPrefix("timelog_") &&
            $0.lastPathComponent.hasSuffix(".csv")
        }
        .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []

        csvFiles = files
        selectedFile = selectedFile ?? files.first
        selectedEntries = selectedFile.map { parseCsvHistory($0) } ?? []
    }

    private func parseCsvHistory(_ file: URL) -> [CsvHistoryEntry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return []
        }

        return text
            .components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return nil
                }

                let parts = splitCsvLine(trimmed)

                guard parts.count >= 5 else {
                    return nil
                }

                return CsvHistoryEntry(
                    date: parts[0],
                    startTime: parts[1],
                    stopTime: parts[2],
                    durationMinutes: parts[3],
                    description: parts.dropFirst(4).joined(separator: ",")
                )
            }
    }

    private func splitCsvLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }

        result.append(current)

        return result.map {
            $0.replacingOccurrences(of: "\"\"", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}


struct ClientsView: View {

    @State private var store = TimeLogStore()
    @State private var selectedClientId = ""
    @State private var newClientName = ""
    @State private var statusText = "Add or select a client"

    private let cardColor = Color(.secondarySystemBackground)

    private var clients: [ClientProfile] {
        store.clients.sorted { $0.clientName < $1.clientName }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                addClientCard
                clientList
            }
            .padding()
        }
        .navigationTitle("Clients")
        .onAppear {
            reloadStore()
        }
    }

    private var addClientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Client")
                .font(.headline)

            TextField("Client name", text: $newClientName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Client name")

            Button("Add Client") {
                addClient()
            }
            .buttonStyle(.borderedProminent)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var clientList: some View {
        VStack(spacing: 12) {
            ForEach(clients, id: \.id) { client in
                clientCard(client)
            }
        }
    }

    private func clientCard(_ client: ClientProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(client.clientName)
                .font(.headline)

            if selectedClientId == client.id {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Select") {
                    selectedClientId = client.id
                    statusText = "Selected \(client.clientName)"
                }
                .buttonStyle(.bordered)

                NavigationLink("Drive") {
                    ClientDriveView(clientId: client.id)
                }
                .buttonStyle(.bordered)

                NavigationLink("Nextcloud") {
                    ClientNextcloudView(clientId: client.id)
                }
                .buttonStyle(.bordered)

                Button("Delete") {
                    deleteClient(client)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Delete \(client.clientName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func addClient() {
        let trimmed = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            statusText = "Client name required"
            return
        }

        store.addClient(clientName: trimmed)
        selectedClientId = store.clients.last?.id ?? ""
        newClientName = ""
        statusText = "Client added"
        reloadStore()
    }

    private func deleteClient(_ client: ClientProfile) {
        store.deleteClient(clientId: client.id)
        statusText = "Deleted \(client.clientName)"
        reloadStore()
    }

    private func reloadStore() {
        store = TimeLogStore()

        if selectedClientId.isEmpty ||
            !store.clients.contains(where: { $0.id == selectedClientId }) {
            selectedClientId = store.clients.first?.id ?? ""
        }
    }
}


struct ClientNextcloudView: View {

    let clientId: String

    @State private var store = TimeLogStore()
    @State private var serverUrl = ""
    @State private var username = ""
    @State private var appPassword = ""
    @State private var remoteFolder = ""
    @State private var statusText = "Edit Nextcloud settings"

    private let cardColor = Color(.secondarySystemBackground)

    private var client: ClientProfile? {
        store.getClientById(clientId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                VStack(alignment: .leading, spacing: 10) {
                    Text(client?.clientName ?? "Client")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(statusText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Nextcloud Server URL")
                        .font(.headline)

                    TextField("https://cloud.example.com", text: $serverUrl)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud server URL")

                    Text("Username")
                        .font(.headline)

                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud username")

                    Text("App Password")
                        .font(.headline)

                    SecureField("App password", text: $appPassword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Nextcloud app password")

                    Text("Remote Folder")
                        .font(.headline)

                    TextField("TimeKeeper", text: $remoteFolder)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud remote folder")

                    Button("Save Nextcloud Settings") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear Nextcloud Settings") {
                        clear()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text("How this works")
                        .font(.headline)

                    Text("Sync will upload CSV files to the selected remote folder, with a client subfolder added automatically if needed.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .navigationTitle("Nextcloud")
        .onAppear {
            load()
        }
    }

    private func load() {
        store = TimeLogStore()

        guard let client else {
            statusText = "Client not found"
            return
        }

        serverUrl = client.nextcloudUrl
        username = client.nextcloudUser
        appPassword = client.nextcloudPassword
        remoteFolder = client.nextcloudFolder.isEmpty ? "TimeKeeper" : client.nextcloudFolder
    }

    private func save() {
        guard let old = client else {
            statusText = "Client not found"
            return
        }

        let updated = ClientProfile(
            id: old.id,
            clientName: old.clientName,
            userName: old.userName,
            csvFileName: old.csvFileName,
            localFolder: old.localFolder,
            googleDriveAccount: old.googleDriveAccount,
            googleDriveFolder: old.googleDriveFolder,
            nextcloudUrl: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            nextcloudUser: username.trimmingCharacters(in: .whitespacesAndNewlines),
            nextcloudPassword: appPassword,
            nextcloudFolder: remoteFolder.trimmingCharacters(in: .whitespacesAndNewlines),
            autoSyncEnabled: old.autoSyncEnabled,
            syncGoogleDriveEnabled: old.syncGoogleDriveEnabled,
            syncNextcloudEnabled: true
        )

        store.updateClient(updated)
        statusText = "Nextcloud settings saved"
        load()
    }

    private func clear() {
        serverUrl = ""
        username = ""
        appPassword = ""
        remoteFolder = "TimeKeeper"
        save()
        statusText = "Nextcloud settings cleared"
    }
}


struct ClientDriveView: View {

    let clientId: String

    @State private var store = TimeLogStore()
    @State private var googleAccount = ""
    @State private var driveFolder = ""
    @State private var enabled = false
    @State private var statusText = "Edit Google Drive settings"

    private let cardColor = Color(.secondarySystemBackground)

    private var client: ClientProfile? {
        store.getClientById(clientId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                VStack(alignment: .leading, spacing: 10) {
                    Text(client?.clientName ?? "Client")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {

                    Toggle("Enable Google Drive Sync", isOn: $enabled)

                    Text("Google Account (placeholder)")
                        .font(.headline)

                    TextField("email@example.com", text: $googleAccount)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)

                    Text("Drive Folder")
                        .font(.headline)

                    TextField("TimeKeeper", text: $driveFolder)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Drive Settings") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .navigationTitle("Google Drive")
        .onAppear {
            load()
        }
    }

    private func load() {
        store = TimeLogStore()

        guard let client else { return }

        googleAccount = client.googleDriveAccount
        driveFolder = client.googleDriveFolder.isEmpty ? "TimeKeeper" : client.googleDriveFolder
        enabled = client.syncGoogleDriveEnabled
    }

    private func save() {
        guard let old = client else { return }

        let updated = ClientProfile(
            id: old.id,
            clientName: old.clientName,
            userName: old.userName,
            csvFileName: old.csvFileName,
            localFolder: old.localFolder,
            googleDriveAccount: googleAccount,
            googleDriveFolder: driveFolder,
            nextcloudUrl: old.nextcloudUrl,
            nextcloudUser: old.nextcloudUser,
            nextcloudPassword: old.nextcloudPassword,
            nextcloudFolder: old.nextcloudFolder,
            autoSyncEnabled: old.autoSyncEnabled,
            syncGoogleDriveEnabled: enabled,
            syncNextcloudEnabled: old.syncNextcloudEnabled
        )

        store.updateClient(updated)
        statusText = "Drive settings saved"
        load()
    }
}
