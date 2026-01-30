import Foundation

enum TMDBDateFormatter {
    static let input: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let output: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let yearOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    static func format(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let date = input.date(from: value) else { return value }
        return output.string(from: date)
    }

    static func year(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let date = input.date(from: value) else { return value }
        return yearOnly.string(from: date)
    }
}
