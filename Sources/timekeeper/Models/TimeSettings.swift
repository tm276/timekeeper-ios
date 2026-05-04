import Foundation

enum DurationUnit: String, Codable {
    case days = "DAYS"
    case weeks = "WEEKS"
    case months = "MONTHS"
}

enum WeekEndDay: String, Codable {
    case sunday = "SUNDAY"
    case monday = "MONDAY"
    case tuesday = "TUESDAY"
    case wednesday = "WEDNESDAY"
    case thursday = "THURSDAY"
    case friday = "FRIDAY"
    case saturday = "SATURDAY"
}

struct TimeSettings: Codable {
    let anchorMillis: Int64
    let durationAmount: Int
    let durationUnit: DurationUnit
    let userName: String
    let weekEndDay: WeekEndDay

    static func `default`() -> TimeSettings {
        TimeSettings(
            anchorMillis: Int64(Date().timeIntervalSince1970 * 1000),
            durationAmount: 1,
            durationUnit: .weeks,
            userName: "",
            weekEndDay: .sunday
        )
    }
}
