import Foundation

enum CsvWindowManager {

    struct Window {
        let key: String
        let startMillis: Int64
        let endMillis: Int64
    }

    static func groupEntriesByWindow(
        entries: [TimeEntry],
        settings: TimeSettings
    ) -> [String: [TimeEntry]] {

        var result: [String: [TimeEntry]] = [:]

        for entry in entries {
            let window = windowFor(entry.startMillis, settings: settings)
            result[window.key, default: []].append(entry)
        }

        return result
    }

    static func windowFor(
        _ millis: Int64,
        settings: TimeSettings
    ) -> Window {

        let calendar = Calendar.current
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)

        switch settings.durationUnit {

        case .days:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: settings.durationAmount, to: start)!

            return Window(
                key: formatKey(start),
                startMillis: millisFromDate(start),
                endMillis: millisFromDate(end)
            )

        case .weeks:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let end = calendar.date(byAdding: .weekOfYear, value: settings.durationAmount, to: start)!

            return Window(
                key: formatKey(start),
                startMillis: millisFromDate(start),
                endMillis: millisFromDate(end)
            )

        case .months:
            let start = calendar.dateInterval(of: .month, for: date)!.start
            let end = calendar.date(byAdding: .month, value: settings.durationAmount, to: start)!

            return Window(
                key: formatKey(start),
                startMillis: millisFromDate(start),
                endMillis: millisFromDate(end)
            )
        }
    }


    static func rewriteAllWindows(
        client: ClientProfile,
        settings: TimeSettings,
        entries: [TimeEntry]
    ) {
        _ = try? CsvShareUtils.writeWindowedCSVs(
            entries: entries,
            client: client,
            settings: settings
        )
    }
    private static func formatKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    private static func millisFromDate(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
