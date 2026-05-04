import Foundation

enum CsvShareUtils {

    static func writeWindowedCSVs(
        entries: [TimeEntry],
        client: ClientProfile,
        settings: TimeSettings
    ) throws -> [URL] {

        let grouped = CsvWindowManager.groupEntriesByWindow(
            entries: entries,
            settings: settings
        )

        var urls: [URL] = []

        for (windowKey, entries) in grouped {
            let url = try writeSingleCSV(
                entries: entries,
                client: client,
                windowKey: windowKey
            )
            urls.append(url)
        }

        return urls
    }

    private static func writeSingleCSV(
        entries: [TimeEntry],
        client: ClientProfile,
        windowKey: String
    ) throws -> URL {

        let folder = clientFolderURL(for: client)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safeClientName = sanitizeFileName(client.clientName)
        let fileName = "timelog_\(safeClientName)_\(windowKey).csv"
        let fileURL = folder.appendingPathComponent(fileName)

        let csv = generateCSV(entries: entries)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    private static func generateCSV(entries: [TimeEntry]) -> String {
        var lines: [String] = []
        lines.append("Date,Start,Stop,Duration Minutes,Description")

        for entry in entries {
            let date = TimeFormatUtils.formatDate(entry.startMillis)
            let start = TimeFormatUtils.formatTime(entry.startMillis)
            let stop = TimeFormatUtils.formatTime(entry.stopMillis)
            let duration = "\(entry.durationMinutes)"
            let description = escape(entry.description)

            lines.append("\(date),\(start),\(stop),\(duration),\(description)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func clientFolderURL(for client: ClientProfile) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = client.localFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "defaultfolder/\(sanitizeFileName(client.clientName))"
            : client.localFolder

        return documents.appendingPathComponent(folder, isDirectory: true)
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "_",
            options: .regularExpression
        )
        let cleaned = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? "client" : cleaned
    }

    private static func escape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }
}
