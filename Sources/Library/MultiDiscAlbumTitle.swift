import Foundation

public struct MultiDiscAlbumTitle: Equatable, Sendable {
    public let baseTitle: String
    public let discNumber: Int

    private static let discSuffixExpression = try! NSRegularExpression(
        pattern: #"\s*[-–—:]?\s*(?:cd|disc|disk)\s*0*(\d+)\s*$"#,
        options: [.caseInsensitive]
    )
    private static let numberedVolumeExpression = try! NSRegularExpression(
        pattern: #"^\s*(.+?)\s*,\s*(?:volume|vol\.?)\s*0*(\d{1,3})(?:\s*[:\-–—]\s*.+)?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let labeledPathExpression = try! NSRegularExpression(
        pattern: #"(?:^|[/\\])(?:cd|disc|disk)\s*0*(\d+)(?=\s*[-_.:]|[/\\]|$)"#,
        options: [.caseInsensitive]
    )
    private static let numberedFolderPathExpression = try! NSRegularExpression(
        pattern: #"(?:^|[/\\])0*(\d{1,2})\s*[-_]\s*[^/\\]+(?=[/\\])"#,
        options: [.caseInsensitive]
    )
    private static let labeledFolderExpression = try! NSRegularExpression(
        pattern: #"^\s*(?:cd|disc|disk|volume|vol\.?)\s*0*(\d{1,2})(?:\s*[-_.:].*)?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let numberedFolderExpression = try! NSRegularExpression(
        pattern: #"^\s*0*(\d{1,2})\s*[-_]\s*.+$"#,
        options: [.caseInsensitive]
    )
    private static let romanNumeralVolumeExpression = try! NSRegularExpression(
        pattern: #"^\s*(.+?)\s*,\s*([ivxlcdm]+)\.\s*.+$"#,
        options: [.caseInsensitive]
    )

    public static func parse(_ title: String) -> MultiDiscAlbumTitle? {
        if let disc = parseDiscSuffix(title) {
            return disc
        }
        return parseNumberedVolume(title)
    }

    private static func parseDiscSuffix(_ title: String) -> MultiDiscAlbumTitle? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = discSuffixExpression.firstMatch(in: title, range: range),
              let suffixRange = Range(match.range, in: title),
              let numberRange = Range(match.range(at: 1), in: title),
              let discNumber = Int(title[numberRange]),
              discNumber > 0 else {
            return nil
        }

        let baseTitle = title[..<suffixRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseTitle.isEmpty else { return nil }

        return MultiDiscAlbumTitle(baseTitle: baseTitle, discNumber: discNumber)
    }

    private static func parseNumberedVolume(_ title: String) -> MultiDiscAlbumTitle? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = numberedVolumeExpression.firstMatch(in: title, range: range),
              let baseRange = Range(match.range(at: 1), in: title),
              let numberRange = Range(match.range(at: 2), in: title),
              let discNumber = Int(title[numberRange]),
              discNumber > 0 else {
            return nil
        }
        let baseTitle = title[baseRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseTitle.isEmpty else { return nil }
        return MultiDiscAlbumTitle(baseTitle: baseTitle, discNumber: discNumber)
    }

    public static func isNumberedVolumeTitle(_ title: String) -> Bool {
        parseNumberedVolume(title) != nil
    }

    public static func infer(
        title: String,
        year: Int,
        trackPaths: [String]
    ) -> MultiDiscAlbumTitle? {
        if let parsed = parse(title) {
            return parsed
        }
        if let parsed = parseRomanNumeralVolume(title) {
            return parsed
        }

        let pathDiscNumbers = trackPaths.compactMap(discNumber(inPath:))
        guard !pathDiscNumbers.isEmpty else { return nil }
        let counts = Dictionary(grouping: pathDiscNumbers, by: { $0 })
        guard let discNumber = counts.max(by: { $0.value.count < $1.value.count })?.key else {
            return nil
        }

        let baseTitle = removingEditionYearSuffix(from: title, matching: year)
        guard !baseTitle.isEmpty else { return nil }
        return MultiDiscAlbumTitle(baseTitle: baseTitle, discNumber: discNumber)
    }

    public static func discNumber(inPath path: String) -> Int? {
        let range = NSRange(path.startIndex..., in: path)
        if let match = labeledPathExpression.firstMatch(in: path, range: range),
           let numberRange = Range(match.range(at: 1), in: path) {
            return Int(path[numberRange])
        }

        let matches = numberedFolderPathExpression.matches(in: path, range: range)
        guard let match = matches.last,
              let numberRange = Range(match.range(at: 1), in: path),
              let number = Int(path[numberRange]),
              number > 0 else {
            return nil
        }
        return number
    }

    public static func collectionFolder(inPath path: String) -> (path: String, name: String, discNumber: Int)? {
        // Imported track paths are already standardized. NSString's lexical
        // path operations avoid Foundation URL parsing and Unicode
        // decomposition for every track in a large library.
        var folderPath = (path as NSString).deletingLastPathComponent

        // Tracks are sometimes nested one level below the disc directory, for
        // example "Box Set/CD 1/FLAC/01.flac".
        for _ in 0..<2 {
            let folderName = (folderPath as NSString).lastPathComponent
            if let discNumber = discNumber(inFolderName: folderName) {
                let collectionPath = (folderPath as NSString).deletingLastPathComponent
                let collectionName = (collectionPath as NSString).lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !collectionName.isEmpty else { return nil }
                return (collectionPath, collectionName, discNumber)
            }
            folderPath = (folderPath as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func discNumber(inFolderName folderName: String) -> Int? {
        for expression in [labeledFolderExpression, numberedFolderExpression] {
            let range = NSRange(folderName.startIndex..., in: folderName)
            guard let match = expression.firstMatch(in: folderName, range: range),
                  let numberRange = Range(match.range(at: 1), in: folderName),
                  let number = Int(folderName[numberRange]),
                  number > 0 else {
                continue
            }
            return number
        }
        return nil
    }

    private static func parseRomanNumeralVolume(_ title: String) -> MultiDiscAlbumTitle? {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = romanNumeralVolumeExpression.firstMatch(in: title, range: range),
              let baseRange = Range(match.range(at: 1), in: title),
              let numeralRange = Range(match.range(at: 2), in: title),
              let discNumber = romanNumeralValue(String(title[numeralRange])),
              discNumber > 0,
              discNumber <= 99 else {
            return nil
        }
        let baseTitle = title[baseRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseTitle.isEmpty else { return nil }
        return MultiDiscAlbumTitle(baseTitle: baseTitle, discNumber: discNumber)
    }

    private static func romanNumeralValue(_ numeral: String) -> Int? {
        let values: [Character: Int] = [
            "I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1_000,
        ]
        let characters = Array(numeral.uppercased())
        guard !characters.isEmpty, characters.allSatisfy({ values[$0] != nil }) else {
            return nil
        }
        var total = 0
        for index in characters.indices {
            let value = values[characters[index]]!
            let next = index < characters.index(before: characters.endIndex)
                ? values[characters[characters.index(after: index)]]!
                : 0
            total += value < next ? -value : value
        }
        return total
    }

    private static func removingEditionYearSuffix(
        from title: String,
        matching year: Int
    ) -> String {
        guard year > 0 else { return title }
        let suffix = #"\s*[-–—:]\s*\#(year)\s*$"#
        guard let range = title.range(
            of: suffix,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return title
        }
        return title[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
