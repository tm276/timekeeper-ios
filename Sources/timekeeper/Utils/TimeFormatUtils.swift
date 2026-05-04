import Foundation

enum TimeFormatUtils {

    static func formatDate(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        return dateFormatter.string(from: date)
    }

    static func formatTime(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        return timeFormatter.string(from: date)
    }

    static func formatDurationMinutes(startMillis: Int64, stopMillis: Int64) -> Int64 {
        max((stopMillis - startMillis) / 60000, 0)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()
}
