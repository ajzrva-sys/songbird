import Foundation

public enum SmartMatchMode: String, Codable, CaseIterable, Sendable {
    case any
    case all
}

public enum SmartLimitUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case songs
    case hours
    case minutes
    case megabytes
    case gigabytes

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .songs: return "songs"
        case .hours: return "hours"
        case .minutes: return "minutes"
        case .megabytes: return "MB"
        case .gigabytes: return "GB"
        }
    }
}

public enum SmartLimitSortOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case random
    case recentlyAdded
    case recentlyPlayed
    case mostOftenPlayed
    case artist
    case album
    case rating

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .random: return "random"
        case .recentlyAdded: return "recently added"
        case .recentlyPlayed: return "recently played"
        case .mostOftenPlayed: return "most often played"
        case .artist: return "artist"
        case .album: return "album"
        case .rating: return "rating"
        }
    }
}

public enum SmartField: String, Codable, CaseIterable, Identifiable, Sendable {
    case title
    case artist
    case album
    case genre
    case composer
    case comment
    case favorite
    case rating
    case playCount
    case year
    case dateAdded
    case lastPlayed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .composer: return "Composer"
        case .comment: return "Comment"
        case .favorite: return "Favorite"
        case .rating: return "Rating"
        case .playCount: return "Play Count"
        case .year: return "Year"
        case .dateAdded: return "Date Added"
        case .lastPlayed: return "Last Played"
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .rating, .playCount, .year: return true
        default: return false
        }
    }

    public var isDate: Bool {
        self == .dateAdded || self == .lastPlayed
    }
}

public enum SmartOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case contains
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case startsWith
    case isSet
    case isNotSet

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .contains: return "contains"
        case .equals: return "is"
        case .notEquals: return "is not"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        case .startsWith: return "starts with"
        case .isSet: return "is set"
        case .isNotSet: return "is not set"
        }
    }

    public static func operators(for field: SmartField) -> [SmartOperator] {
        if field == .favorite {
            return [.isSet, .isNotSet]
        }
        if field == .lastPlayed {
            return [.isSet, .isNotSet, .equals, .notEquals, .greaterThan, .lessThan]
        }
        if field.isNumeric || field.isDate {
            return [.equals, .notEquals, .greaterThan, .lessThan]
        }
        return [.contains, .equals, .notEquals, .startsWith]
    }

    public var requiresValue: Bool {
        self != .isSet && self != .isNotSet
    }
}

public enum SmartPlaylistValidationError: Error, LocalizedError, Equatable, Sendable {
    case noConditions
    case invalidOperator(conditionID: UUID)
    case missingValue(conditionID: UUID)
    case invalidValue(conditionID: UUID, message: String)

    public var errorDescription: String? {
        switch self {
        case .noConditions:
            return "Add at least one condition."
        case .invalidOperator:
            return "Choose an operator that is valid for this field."
        case .missingValue:
            return "Enter a value for this condition."
        case .invalidValue(_, let message):
            return message
        }
    }
}

public struct SmartCondition: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var field: SmartField
    public var op: SmartOperator
    public var value: String

    public init(
        id: UUID = UUID(),
        field: SmartField = .genre,
        op: SmartOperator = .contains,
        value: String = ""
    ) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }
}

public struct SmartPlaylistRuleSet: Codable, Equatable, Sendable {
    public var matchMode: SmartMatchMode
    public var conditions: [SmartCondition]
    public var limitEnabled: Bool
    public var limitCount: Int
    public var limitUnit: SmartLimitUnit
    public var limitSortOrder: SmartLimitSortOrder

    public init(
        matchMode: SmartMatchMode = .all,
        conditions: [SmartCondition] = [],
        limitEnabled: Bool = false,
        limitCount: Int = 25,
        limitUnit: SmartLimitUnit = .songs,
        limitSortOrder: SmartLimitSortOrder = .random
    ) {
        self.matchMode = matchMode
        self.conditions = conditions
        self.limitEnabled = limitEnabled
        self.limitCount = limitCount
        self.limitUnit = limitUnit
        self.limitSortOrder = limitSortOrder
    }

    public static func decode(from data: Data?) -> SmartPlaylistRuleSet? {
        guard let data else { return nil }
        guard var decoded = try? JSONDecoder().decode(SmartPlaylistRuleSet.self, from: data) else {
            return nil
        }
        decoded.conditions = decoded.conditions.map { condition in
            var condition = condition
            let operators = SmartOperator.operators(for: condition.field)
            if operators.contains(condition.op) == false {
                condition.op = operators[0]
            }
            if condition.op.requiresValue == false {
                condition.value = ""
            }
            return condition
        }
        return decoded
    }

    public func encode() throws -> Data {
        if let error = validationErrors.first { throw error }
        return try JSONEncoder().encode(self)
    }

    public var validationErrors: [SmartPlaylistValidationError] {
        guard conditions.isEmpty == false else { return [.noConditions] }
        return conditions.compactMap(Self.validationError(for:))
    }

    public static func validationError(for condition: SmartCondition) -> SmartPlaylistValidationError? {
        guard SmartOperator.operators(for: condition.field).contains(condition.op) else {
            return .invalidOperator(conditionID: condition.id)
        }
        guard condition.op.requiresValue else { return nil }

        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return .missingValue(conditionID: condition.id)
        }

        if condition.field.isNumeric || condition.field.isDate {
            guard let number = Int(value), String(number) == value || "+\(number)" == value else {
                return .invalidValue(
                    conditionID: condition.id,
                    message: condition.field.isDate
                        ? "Enter a whole number of days."
                        : "Enter a whole number."
                )
            }
            switch condition.field {
            case .rating where !(0...5).contains(number):
                return .invalidValue(conditionID: condition.id, message: "Rating must be between 0 and 5.")
            case .playCount where number < 0:
                return .invalidValue(conditionID: condition.id, message: "Play Count cannot be negative.")
            case .year where !(0...9999).contains(number):
                return .invalidValue(conditionID: condition.id, message: "Year must be between 0 and 9999.")
            case .dateAdded where number < 0, .lastPlayed where number < 0:
                return .invalidValue(conditionID: condition.id, message: "Days cannot be negative.")
            default:
                break
            }
        }
        return nil
    }

    public func matches(_ track: Track) -> Bool {
        guard !conditions.isEmpty else { return true }
        let results = conditions.map { evaluate($0, track: track) }
        switch matchMode {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        }
    }

    public func filter(_ tracks: [Track]) -> [Track] {
        tracks.filter { matches($0) }
    }

    public func matches(_ track: LibraryTrackSnapshot) -> Bool {
        guard !conditions.isEmpty else { return true }
        let results = conditions.map { evaluate($0, track: track) }
        switch matchMode {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        }
    }

    public func filter(_ tracks: [LibraryTrackSnapshot]) -> [LibraryTrackSnapshot] {
        tracks.filter { matches($0) }
    }

    private func evaluate(_ condition: SmartCondition, track: Track) -> Bool {
        let value = condition.value
        switch condition.field {
        case .title:
            return compareString(track.title, op: condition.op, value: value)
        case .artist:
            return compareString(track.artist, op: condition.op, value: value)
        case .album:
            return compareString(track.album, op: condition.op, value: value)
        case .genre:
            return compareString(track.genre, op: condition.op, value: value)
        case .composer:
            return compareString(track.composer, op: condition.op, value: value)
        case .comment:
            return compareString(track.comment, op: condition.op, value: value)
        case .favorite:
            // TrackFavorite is a separate model; value-backed filtering is the
            // canonical smart-playlist path.
            return false
        case .rating:
            return compareNumber(Double(track.rating), op: condition.op, value: value)
        case .playCount:
            return compareNumber(Double(track.playCount), op: condition.op, value: value)
        case .year:
            return compareNumber(Double(track.year), op: condition.op, value: value)
        case .dateAdded:
            let days = Calendar.current.dateComponents([.day], from: track.dateAdded, to: Date()).day ?? 0
            return compareNumber(Double(days), op: condition.op, value: value)
        case .lastPlayed:
            if condition.op == .isSet { return track.lastPlayed != nil }
            if condition.op == .isNotSet { return track.lastPlayed == nil }
            guard let last = track.lastPlayed else { return false }
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            return compareNumber(Double(days), op: condition.op, value: value)
        }
    }

    private func evaluate(_ condition: SmartCondition, track: LibraryTrackSnapshot) -> Bool {
        let value = condition.value
        switch condition.field {
        case .title: return compareString(track.title, op: condition.op, value: value)
        case .artist: return compareString(track.artist, op: condition.op, value: value)
        case .album: return compareString(track.album, op: condition.op, value: value)
        case .genre: return compareString(track.genre, op: condition.op, value: value)
        case .composer: return compareString(track.composer, op: condition.op, value: value)
        case .comment: return compareString(track.comment, op: condition.op, value: value)
        case .favorite:
            return condition.op == .isSet ? track.isLoved : !track.isLoved
        case .rating: return compareNumber(Double(track.rating), op: condition.op, value: value)
        case .playCount: return compareNumber(Double(track.playCount), op: condition.op, value: value)
        case .year: return compareNumber(Double(track.year), op: condition.op, value: value)
        case .dateAdded:
            let days = Calendar.current.dateComponents([.day], from: track.dateAdded, to: Date()).day ?? 0
            return compareNumber(Double(days), op: condition.op, value: value)
        case .lastPlayed:
            if condition.op == .isSet { return track.lastPlayed != nil }
            if condition.op == .isNotSet { return track.lastPlayed == nil }
            guard let lastPlayed = track.lastPlayed else { return false }
            let days = Calendar.current.dateComponents([.day], from: lastPlayed, to: Date()).day ?? 0
            return compareNumber(Double(days), op: condition.op, value: value)
        }
    }

    private func compareString(_ lhs: String, op: SmartOperator, value: String) -> Bool {
        switch op {
        case .contains: return lhs.localizedCaseInsensitiveContains(value)
        case .equals: return lhs.localizedCaseInsensitiveCompare(value) == .orderedSame
        case .notEquals: return lhs.localizedCaseInsensitiveCompare(value) != .orderedSame
        case .startsWith: return lhs.lowercased().hasPrefix(value.lowercased())
        case .greaterThan, .lessThan, .isSet, .isNotSet: return false
        }
    }

    private func compareNumber(_ lhs: Double, op: SmartOperator, value: String) -> Bool {
        guard let rhs = Double(value) else { return false }
        switch op {
        case .equals: return lhs == rhs
        case .notEquals: return lhs != rhs
        case .greaterThan: return lhs > rhs
        case .lessThan: return lhs < rhs
        default: return false
        }
    }
}
