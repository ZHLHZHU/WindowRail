import Foundation

enum WindowSearch {
    static func matches(_ query: String, title: String, applicationName: String) -> Bool {
        let text = applicationName + " " + title
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { term in
            text.range(of: String(term), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                       locale: .current) != nil
        }
    }
}
