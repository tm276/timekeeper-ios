import Foundation

struct TimeEntry: Codable, Identifiable {
    let id: UUID
    let clientId: String
    let startMillis: Int64
    let stopMillis: Int64
    let description: String
    let durationMinutes: Int64

    init(
        id: UUID = UUID(),
        clientId: String,
        startMillis: Int64,
        stopMillis: Int64,
        description: String,
        durationMinutes: Int64
    ) {
        self.id = id
        self.clientId = clientId
        self.startMillis = startMillis
        self.stopMillis = stopMillis
        self.description = description
        self.durationMinutes = durationMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case clientId
        case startMillis
        case stopMillis
        case description
        case durationMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.clientId = try c.decode(String.self, forKey: .clientId)
        self.startMillis = try c.decode(Int64.self, forKey: .startMillis)
        self.stopMillis = try c.decode(Int64.self, forKey: .stopMillis)
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.durationMinutes = try c.decode(Int64.self, forKey: .durationMinutes)
    }
}
