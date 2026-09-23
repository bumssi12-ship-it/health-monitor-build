import Foundation

enum CSVSanitizer {
    static func escape(_ original: String) -> String {
        let value = protectSpreadsheetFormula(original)

        if value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r") {
            let escaped = value.replacingOccurrences(
                of: "\"",
                with: "\"\""
            )
            return "\"" + escaped + "\""
        }

        return value
    }

    static func protectSpreadsheetFormula(
        _ value: String
    ) -> String {
        let trimmed = value.drop {
            $0.isWhitespace
                || $0 == "\u{FEFF}"
        }

        guard let first = trimmed.first else {
            return value
        }

        let dangerous: Set<Character> = [
            "=",
            "+",
            "-",
            "@"
        ]

        guard dangerous.contains(first) else {
            return value
        }

        if Double(String(trimmed)) != nil {
            return value
        }

        return "'" + value
    }
}
