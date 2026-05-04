import Foundation

struct NextcloudSettings: Codable {
    let serverUrl: String
    let username: String
    let appPassword: String
    let remoteFolder: String
}
