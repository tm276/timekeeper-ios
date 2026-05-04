import Foundation

struct ClientProfile: Codable, Identifiable {
    let id: String
    let clientName: String
    let userName: String
    let csvFileName: String

    // Local storage
    let localFolder: String

    // Google Drive
    let googleDriveAccount: String
    let googleDriveFolder: String

    // Nextcloud
    let nextcloudUrl: String
    let nextcloudUser: String
    let nextcloudPassword: String
    let nextcloudFolder: String

    // Auto sync settings
    let autoSyncEnabled: Bool
    let syncGoogleDriveEnabled: Bool
    let syncNextcloudEnabled: Bool

    init(
        id: String,
        clientName: String,
        userName: String = "",
        csvFileName: String = "time_log.csv",
        localFolder: String = "",
        googleDriveAccount: String = "",
        googleDriveFolder: String = "",
        nextcloudUrl: String = "",
        nextcloudUser: String = "",
        nextcloudPassword: String = "",
        nextcloudFolder: String = "",
        autoSyncEnabled: Bool = false,
        syncGoogleDriveEnabled: Bool = false,
        syncNextcloudEnabled: Bool = false
    ) {
        self.id = id
        self.clientName = clientName
        self.userName = userName
        self.csvFileName = csvFileName
        self.localFolder = localFolder
        self.googleDriveAccount = googleDriveAccount
        self.googleDriveFolder = googleDriveFolder
        self.nextcloudUrl = nextcloudUrl
        self.nextcloudUser = nextcloudUser
        self.nextcloudPassword = nextcloudPassword
        self.nextcloudFolder = nextcloudFolder
        self.autoSyncEnabled = autoSyncEnabled
        self.syncGoogleDriveEnabled = syncGoogleDriveEnabled
        self.syncNextcloudEnabled = syncNextcloudEnabled
    }
}
