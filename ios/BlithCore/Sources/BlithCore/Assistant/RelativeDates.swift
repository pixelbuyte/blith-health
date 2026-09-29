import Foundation

/// Resolves the day a question refers to ("yesterday", "last Tuesday", "Sep 21", "2026-09-21").
public enum RelativeDates {
    public static func day(in text: String, today: LocalDate) -> LocalDate? {
        let t = text.lowercased()
        if t.contains("yesterday") { return today.adding(days: -1) }
        if let r = t.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression), let d = LocalDate(string: String(t[r])) { return d }
        for (i, name) in Fmt.weekdayNames.enumerated() {
            let n = name.lowercased()
            guard t.contains(n) else { continue }
            // Most recent such weekday before today ("last Tuesday" on a Tuesday = a week ago).
            var d = today.adding(days: -1)
            while d.weekday != i + 1 { d = d.adding(days: -1) }
            return d
        }
        for (i, month) in Fmt.monthNames.enumerated() {
            let names = [month.lowercased(), String(month.lowercased().prefix(3))]
            for m in names {
                if let r = t.range(of: m + #"\.? (\d{1,2})\b"#, options: .regularExpression) {
                    let digits = t[r].filter(\.isNumber)
                    if let day = Int(digits), (1...31).contains(day) {
                        var d = LocalDate(year: today.year, month: i + 1, day: day)
                        if d > today { d = LocalDate(year: today.year - 1, month: i + 1, day: day) }
                        return d
                    }
                }
            }
        }
        if t.contains("today") { return today }
        return nil
    }
}
