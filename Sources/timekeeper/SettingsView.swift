import SwiftUI
import AuthenticationServices
import CoreLocation
import UIKit

private let settingsAppBackground = Color(red: 0.07, green: 0.07, blue: 0.07)
private let settingsPanelBackground = Color(red: 0.12, green: 0.12, blue: 0.12)
private let settingsCardBackground = Color(red: 0.15, green: 0.20, blue: 0.22)
private let settingsPrimaryAction = Color(red: 0.39, green: 0.71, blue: 0.96)
private let settingsSecondaryAction = Color(red: 0.22, green: 0.28, blue: 0.31)
private let settingsDangerAction = Color(red: 0.90, green: 0.45, blue: 0.45)
private let settingsPrimaryText = Color(red: 0.96, green: 0.96, blue: 0.96)
private let settingsSecondaryText = Color(red: 0.81, green: 0.85, blue: 0.86)

private func defaultRemoteClientFolder(_ clientName: String) -> String {
    let safe = clientName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return "TimeKeeper/\(safe.isEmpty ? "client" : safe)"
}

struct SettingsView: View, @unchecked Sendable {

    let clientId: String

    @State private var store = TimeLogStore()
    @State private var userName = ""
    @State private var weekEndDay: WeekEndDay = .sunday
    @State private var statusText = ""

    @State private var nextcloudUrl = ""
    @State private var nextcloudUser = ""
    @State private var nextcloudPassword = ""
    @State private var nextcloudFolder = ""
    @State private var googleDriveAccount = ""
    @State private var googleDriveFolder = ""
    @State private var autoSyncEnabled = false
    @State private var syncGoogleDriveEnabled = false
    @State private var syncNextcloudEnabled = false

    @State private var showGoogleDriveConnect = false
    @State private var showNextcloudConnect = false
    @State private var showNextcloudManual = false
    @State private var showLocalFiles = false
    @State private var showDeleteEntriesConfirm = false
    @State private var isConnectingNextcloud = false
    @State private var isConnectingDrive = false
    @State private var isSyncing = false
    @State private var showWeekEndingOptions = false

    @State private var localFiles: [URL] = []
    @State private var workSites: [WorkSite] = []
    @State private var showAddSite = false
    @State private var newSiteName = ""
    @State private var newSiteLatitude = ""
    @State private var newSiteLongitude = ""
    @State private var newSiteRadius = "100"
    @State private var siteStatusText = ""
    @State private var selectedFiles: Set<String> = []

    private var client: ClientProfile? { store.getClientById(clientId) }

    private var previewFileName: String {
        let settings = store.settings
        let window = CsvWindowManager.windowFor(
            Int64(Date().timeIntervalSince1970 * 1000),
            settings: settings
        )
        let safe = (client?.clientName ?? "client")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "timelog_\(safe.isEmpty ? "client" : safe)_\(window.key).csv"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                identityCard
                syncCard
                csvWindowCard
                servicesCard
                localFilesCard
                workSitesCard
                repairCard
                dangerCard
                if !statusText.isEmpty {
                    Text(statusText)
                        .foregroundStyle(settingsSecondaryText)
                        .padding(.bottom, 8)
                }
            }
            .padding(12)
        }
        .background(settingsAppBackground)
        .navigationTitle("\(client?.clientName ?? "Client") Settings")
        .onAppear { load() }
        .alert("Delete all client entries?", isPresented: $showDeleteEntriesConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteEntriesForClient(clientId: clientId)
                if let c = client {
                    CsvWindowManager.rewriteAllWindows(client: c, settings: store.settings, entries: [])
                }
                statusText = "Deleted all client entries."
                reloadLocalFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all saved time entries for this client.")
        }
    }

    // MARK: - Sections

    private var identityCard: some View {
        settingsCard {
            Text("Identity")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            TextField("Your Name", text: $userName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Your name")
            Text("This name is written into CSV rows.")
                .foregroundStyle(settingsSecondaryText)
            actionButton("Save Name") {
                saveClient()
                statusText = "Name saved."
            }
        }
    }

    private var syncCard: some View {
        settingsCard {
            Text("Sync")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            actionButton(isSyncing ? "Syncing..." : "Manual Sync Now") {
                guard !isSyncing else { return }
                runManualSync()
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .foregroundStyle(settingsSecondaryText)
            }
            Toggle("Auto sync", isOn: $autoSyncEnabled)
                .foregroundStyle(settingsPrimaryText)
                .onChange(of: autoSyncEnabled) { _, _ in saveClient() }
            Toggle("Enable Google Drive sync", isOn: $syncGoogleDriveEnabled)
                .foregroundStyle(settingsPrimaryText)
                .onChange(of: syncGoogleDriveEnabled) { _, _ in saveClient() }
            Toggle("Enable Nextcloud sync", isOn: $syncNextcloudEnabled)
                .foregroundStyle(settingsPrimaryText)
                .onChange(of: syncNextcloudEnabled) { _, _ in saveClient() }
        }
    }

    private var csvWindowCard: some View {
        settingsCard {
            Text("CSV Window")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Create a new CSV file every week.")
                .foregroundStyle(settingsSecondaryText)
            weekEndPicker
            VStack(alignment: .leading, spacing: 6) {
                Text("Current File").foregroundStyle(settingsSecondaryText)
                Text(previewFileName)
                    .fontWeight(.bold).foregroundStyle(settingsPrimaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(settingsCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            actionButton("Save Weekly Window") {
                saveClient()
                statusText = "Weekly CSV window saved."
                reloadLocalFiles()
            }
        }
    }

    private var weekEndPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showWeekEndingOptions.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week Ends On").foregroundStyle(settingsSecondaryText)
                    Text(weekEndDay.displayName())
                        .fontWeight(.bold).foregroundStyle(settingsPrimaryText)
                    Text(showWeekEndingOptions ? "Tap a day below to choose." : "Tap to choose a different day.")
                        .foregroundStyle(settingsSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityLabel("Week ends on \(weekEndDay.displayName()). Tap to change.")

            if showWeekEndingOptions {
                VStack(spacing: 4) {
                    ForEach([WeekEndDay.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday], id: \.self) { day in
                        Button {
                            weekEndDay = day
                            showWeekEndingOptions = false
                        } label: {
                            HStack {
                                Image(systemName: weekEndDay == day ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(settingsPrimaryAction)
                                Text(day.displayName())
                                    .fontWeight(weekEndDay == day ? .bold : .regular)
                                    .foregroundStyle(settingsPrimaryText)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal)
                        }
                        .accessibilityLabel(day.displayName())
                        .accessibilityAddTraits(weekEndDay == day ? .isSelected : [])
                    }
                }
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var servicesCard: some View {
        settingsCard {
            Text("Services")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            googleDriveSection
            nextcloudSection
            nextcloudManualSection
        }
    }

    private var googleDriveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionButton("Connect to Google Drive") {
                showGoogleDriveConnect.toggle()
                if showGoogleDriveConnect {
                    showNextcloudConnect = false
                    showNextcloudManual = false
                }
            }
            if showGoogleDriveConnect {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default folder: \(defaultRemoteClientFolder(client?.clientName ?? "client"))")
                        .foregroundStyle(settingsSecondaryText)
                    TextField("Google Drive folder", text: $googleDriveFolder)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Google Drive folder")
                    if !googleDriveAccount.isEmpty {
                        Text("Signed in as: \(googleDriveAccount)")
                            .foregroundStyle(settingsSecondaryText)
                    }
                    if GoogleDriveAuthManager.isSignedIn() {
                        dangerButton("Sign Out of Google Drive", disabled: false) {
                            GoogleDriveAuthManager.clearToken()
                            googleDriveAccount = ""
                            syncGoogleDriveEnabled = false
                            saveClient()
                            statusText = "Signed out of Google Drive."
                        }
                    } else {
                        actionButton(isConnectingDrive ? "Signing in..." : "Sign in with Google") {
                            guard !isConnectingDrive else { return }
                            Task { await startGoogleDriveSignIn() }
                        }
                    }
                    actionButton("Save Google Drive Folder") {
                        saveClient()
                        statusText = "Google Drive settings saved."
                    }
                }
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var nextcloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionButton("Connect to Nextcloud") {
                showNextcloudConnect.toggle()
                if showNextcloudConnect {
                    showGoogleDriveConnect = false
                    showNextcloudManual = false
                }
            }
            if showNextcloudConnect {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Server URL", text: $nextcloudUrl)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud server URL")
                    TextField("Remote folder", text: $nextcloudFolder)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud remote folder")
                    if !nextcloudUser.isEmpty {
                        Text("Signed in as: \(nextcloudUser)")
                            .foregroundStyle(settingsSecondaryText)
                    }
                    if isConnectingNextcloud {
                        Text("Waiting for browser login...")
                            .foregroundStyle(settingsSecondaryText)
                    }
                    actionButton(isConnectingNextcloud ? "Waiting for login..." : "Open Browser Login") {
                        guard !isConnectingNextcloud else { return }
                        startNextcloudBrowserLogin()
                    }
                }
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var nextcloudManualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            secondaryButton("Manual Nextcloud Setup") {
                showNextcloudManual.toggle()
                if showNextcloudManual {
                    showNextcloudConnect = false
                    showGoogleDriveConnect = false
                }
            }
            if showNextcloudManual {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Server URL", text: $nextcloudUrl)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud server URL")
                    TextField("Username", text: $nextcloudUser)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud username")
                    SecureField("App Password", text: $nextcloudPassword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Nextcloud app password")
                    TextField("Remote folder", text: $nextcloudFolder)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Nextcloud remote folder")
                    actionButton("Save Manual Setup") {
                        saveClient()
                        statusText = "Manual Nextcloud settings saved."
                    }
                }
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var workSitesCard: some View {
        settingsCard {
            Text("Work Sites")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Add locations for this client. When you tap Start, the app checks if you are at the right site.")
                .foregroundStyle(settingsSecondaryText)

            if workSites.isEmpty {
                Text("No work sites added yet.")
                    .foregroundStyle(settingsSecondaryText)
            } else {
                ForEach(workSites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.siteName)
                            .fontWeight(.bold)
                            .foregroundStyle(settingsPrimaryText)
                        Text("\(String(format: "%.6f", site.latitude)), \(String(format: "%.6f", site.longitude))")
                            .foregroundStyle(settingsSecondaryText)
                        Text("Radius: \(Int(site.radiusMeters))m")
                            .foregroundStyle(settingsSecondaryText)
                        dangerButton("Delete", disabled: false) {
                            WorkSiteStore().deleteSite(siteId: site.id)
                            reloadWorkSites()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(settingsCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            secondaryButton(showAddSite ? "Cancel" : "Add Work Site") {
                showAddSite.toggle()
                newSiteName = ""
                newSiteLatitude = ""
                newSiteLongitude = ""
                newSiteRadius = "100"
                siteStatusText = ""
            }

            if showAddSite {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Site name", text: $newSiteName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Site name")

                    TextField("Latitude (e.g. 37.7749)", text: $newSiteLatitude)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Latitude")

                    TextField("Longitude (e.g. -122.4194)", text: $newSiteLongitude)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Longitude")

                    TextField("Radius in meters (default 100)", text: $newSiteRadius)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Radius in meters")

                    if !siteStatusText.isEmpty {
                        Text(siteStatusText)
                            .foregroundStyle(settingsSecondaryText)
                    }

                    actionButton("Use Current Location") {
                        useCurrentLocationForSite()
                    }

                    actionButton("Save Work Site") {
                        saveWorkSite()
                    }
                }
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var localFilesCard: some View {
        settingsCard {
            secondaryButton("Local Files") {
                showLocalFiles.toggle()
                if showLocalFiles { reloadLocalFiles() }
            }
            if showLocalFiles {
                VStack(alignment: .leading, spacing: 10) {
                    if localFiles.isEmpty {
                        Text("No local CSV files for this client.")
                            .foregroundStyle(settingsSecondaryText)
                    } else {
                        ForEach(localFiles, id: \.lastPathComponent) { file in
                            let name = file.lastPathComponent
                            let isChecked = selectedFiles.contains(name)
                            Button {
                                if isChecked { selectedFiles.remove(name) }
                                else { selectedFiles.insert(name) }
                            } label: {
                                HStack {
                                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(settingsPrimaryAction)
                                    Text(name)
                                        .foregroundStyle(settingsPrimaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityLabel(name)
                            .accessibilityAddTraits(isChecked ? .isSelected : [])
                        }
                        dangerButton("Delete Selected Files", disabled: selectedFiles.isEmpty) {
                            var count = 0
                            for name in selectedFiles {
                                if store.deleteLocalFileForClient(clientId: clientId, fileName: name) { count += 1 }
                            }
                            selectedFiles.removeAll()
                            reloadLocalFiles()
                            statusText = count > 0 ? "Deleted \(count) file(s)." : "No files deleted."
                        }
                    }
                    dangerButton("Delete All Local Files", disabled: false) {
                        let count = store.deleteAllLocalFilesForClient(clientId: clientId)
                        selectedFiles.removeAll()
                        reloadLocalFiles()
                        statusText = count > 0 ? "Deleted \(count) file(s)." : "No files found."
                    }
                }
                .padding()
                .background(settingsCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var repairCard: some View {
        settingsCard {
            Text("Repair")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Regenerate local CSV files from saved time entries.")
                .foregroundStyle(settingsSecondaryText)
            actionButton("Regenerate CSV Files") {
                if let c = client {
                    CsvWindowManager.rewriteAllWindows(
                        client: c,
                        settings: store.settings,
                        entries: store.getEntriesForClient(clientId: clientId)
                    )
                }
                reloadLocalFiles()
                statusText = "CSV files regenerated."
            }
        }
    }

    private var dangerCard: some View {
        settingsCard {
            Text("Danger Zone")
                .font(.headline).fontWeight(.bold)
                .foregroundStyle(settingsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            dangerButton("Delete All Client Entries", disabled: false) {
                showDeleteEntriesConfirm = true
            }
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(settingsPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .background(settingsPrimaryAction)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func secondaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .background(settingsSecondaryAction)
        .foregroundStyle(settingsPrimaryText)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func dangerButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .background(disabled ? settingsSecondaryAction : settingsDangerAction)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(disabled)
    }

    // MARK: - Logic

    private func startNextcloudBrowserLogin() {
        isConnectingNextcloud = true
        statusText = "Opening browser for Nextcloud sign-in..."
        let url = nextcloudUrl
        Task { @MainActor [self] in
            let initResult = await NextcloudLoginFlowManager.startLogin(serverUrl: url)
            guard let initData = try? initResult.get() else {
                self.statusText = "Unable to start Nextcloud sign-in."
                self.isConnectingNextcloud = false
                return
            }
            NextcloudLoginFlowManager.openInBrowser(initData.loginUrl)
            let pollResult = await NextcloudLoginFlowManager.pollForResult(init: initData)
            switch pollResult {
            case .success(let login):
                self.nextcloudUrl = login.server
                self.nextcloudUser = login.loginName
                self.nextcloudPassword = login.appPassword
                self.saveClient()
                self.statusText = "Nextcloud connected as \(login.loginName)."
            case .failure(let error):
                self.statusText = error.localizedDescription
            }
            self.isConnectingNextcloud = false
        }
    }

    private func startGoogleDriveSignIn() async {
        isConnectingDrive = true
        statusText = "Opening Google sign-in..."
        let window = await MainActor.run {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        guard let window else {
            isConnectingDrive = false
            statusText = "Could not find window for sign-in."
            return
        }
        let result = await GoogleDriveAuthManager.signIn(presentingWindow: window)
        switch result {
        case .success(let token):
            googleDriveAccount = token.email
            syncGoogleDriveEnabled = true
            saveClient()
            statusText = "Google Drive connected as \(token.email)."
        case .failure(let error):
            statusText = error.localizedDescription
        }
        isConnectingDrive = false
    }

    private func runManualSync() {
        isSyncing = true
        statusText = "Syncing..."
        let result = SyncOrchestrator.sync(store: store)
        switch result {
        case .success(let message): statusText = message
        case .failure(let error): statusText = error.localizedDescription
        }
        store = TimeLogStore()
        isSyncing = false
    }

    private func load() {
        store = TimeLogStore()
        guard let c = client else { return }
        userName = store.settings.userName
        weekEndDay = store.settings.weekEndDay
        nextcloudUrl = c.nextcloudUrl
        nextcloudUser = c.nextcloudUser
        nextcloudPassword = c.nextcloudPassword
        nextcloudFolder = c.nextcloudFolder.isEmpty ? defaultRemoteClientFolder(c.clientName) : c.nextcloudFolder
        googleDriveAccount = c.googleDriveAccount
        googleDriveFolder = c.googleDriveFolder.isEmpty ? defaultRemoteClientFolder(c.clientName) : c.googleDriveFolder
        autoSyncEnabled = c.autoSyncEnabled
        syncGoogleDriveEnabled = c.syncGoogleDriveEnabled
        syncNextcloudEnabled = c.syncNextcloudEnabled
        reloadLocalFiles()
        reloadWorkSites()
    }

    private func saveClient() {
        guard let old = client else { return }
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedSettings = TimeSettings(
            anchorMillis: store.settings.anchorMillis,
            durationAmount: 1,
            durationUnit: .weeks,
            userName: trimmedName,
            weekEndDay: weekEndDay
        )
        store.updateSettings(updatedSettings)
        let updated = ClientProfile(
            id: old.id,
            clientName: old.clientName,
            userName: trimmedName,
            csvFileName: old.csvFileName,
            localFolder: old.localFolder,
            googleDriveAccount: googleDriveAccount.trimmingCharacters(in: .whitespacesAndNewlines),
            googleDriveFolder: googleDriveFolder.trimmingCharacters(in: .whitespacesAndNewlines),
            nextcloudUrl: nextcloudUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            nextcloudUser: nextcloudUser.trimmingCharacters(in: .whitespacesAndNewlines),
            nextcloudPassword: nextcloudPassword,
            nextcloudFolder: nextcloudFolder.trimmingCharacters(in: .whitespacesAndNewlines),
            autoSyncEnabled: autoSyncEnabled,
            syncGoogleDriveEnabled: syncGoogleDriveEnabled,
            syncNextcloudEnabled: syncNextcloudEnabled
        )
        store.updateClient(updated)
    }

    private func reloadWorkSites() {
        workSites = WorkSiteStore().sitesForClient(clientId)
    }

    private func useCurrentLocationForSite() {
        print("[Location] useCurrentLocationForSite called")
        siteStatusText = "Getting location..."
        let provider = CurrentLocationProvider()
        Task {
            let location = await provider.getCurrentLocation()
            if let location {
                newSiteLatitude = String(format: "%.6f", location.coordinate.latitude)
                newSiteLongitude = String(format: "%.6f", location.coordinate.longitude)
                siteStatusText = "Location captured."
            } else {
                siteStatusText = "Could not get location. Check permissions."
            }
        }
    }

    private func saveWorkSite() {
        guard let lat = Double(newSiteLatitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(newSiteLongitude.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            siteStatusText = "Invalid latitude or longitude."
            return
        }

        let radius = Double(newSiteRadius.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 100.0
        let name = newSiteName.trimmingCharacters(in: .whitespacesAndNewlines)

        WorkSiteStore().addSite(
            clientId: clientId,
            siteName: name.isEmpty ? "Work site" : name,
            latitude: lat,
            longitude: lon,
            radiusMeters: radius
        )

        newSiteName = ""
        newSiteLatitude = ""
        newSiteLongitude = ""
        newSiteRadius = "100"
        siteStatusText = "Work site saved."
        showAddSite = false
        reloadWorkSites()
    }

    private func reloadLocalFiles() {
        localFiles = store.getLocalFilesForClient(clientId: clientId)
    }
}

extension WeekEndDay {
    func displayName() -> String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}
