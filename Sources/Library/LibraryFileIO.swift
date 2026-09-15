import Foundation

public actor LibraryFileIO {
    public static let shared = LibraryFileIO()

    public init() {}

    public func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func lyrics(forAudioPath path: String) throws -> String? {
        guard case .available(let audioURL) = FilesystemPathResolver().resolve(path) else {
            return nil
        }
        let base = (audioURL.path as NSString).deletingPathExtension
        for fileExtension in ["lrc", "txt", "lyrics"] {
            let candidate = URL(fileURLWithPath: base).appendingPathExtension(fileExtension)
            guard case .available(let url) = FilesystemPathResolver().resolve(candidate.path) else {
                continue
            }
            let raw = try String(contentsOf: url, encoding: .utf8)
            return Self.stripLRC(raw)
        }
        return nil
    }

    private static func stripLRC(_ raw: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { line -> String in
            var value = String(line)
            while let open = value.firstIndex(of: "["),
                  let close = value.firstIndex(of: "]"),
                  open < close {
                value.removeSubrange(open...close)
            }
            return value.trimmingCharacters(in: .whitespaces)
        }
        let body = cleaned.filter { $0.isEmpty == false }.joined(separator: "\n")
        return body.isEmpty ? raw : body
    }
}
