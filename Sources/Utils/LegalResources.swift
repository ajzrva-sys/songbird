import Foundation

enum LegalDocument: String, CaseIterable {
    case license = "GPL-3.0"
    case notice = "Songbird-NOTICE"
    case thirdParty = "THIRD-PARTY-NOTICES"
    case source = "CORRESPONDING-SOURCE"
}

enum LegalResources {
    enum Failure: Error {
        case unavailable
    }

    static func read(_ document: LegalDocument) throws -> String {
        try resolve(
            packagedApplication: Bundle.main.bundleURL.pathExtension.lowercased() == "app",
            packaged: { try text(document, in: .main, directory: "Legal") },
            development: {
                // Keep lazy: SwiftPM's generated accessor can trap if its bundle is absent.
                try text(document, in: .module, directory: "Resources/Legal")
            }
        )
    }

    static func resolve(
        packagedApplication: Bool,
        packaged: () throws -> String?,
        development: () throws -> String?
    ) throws -> String {
        let value: String?
        if let packagedText = try packaged() {
            value = packagedText
        } else if packagedApplication {
            throw Failure.unavailable
        } else {
            value = try development()
        }
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.unavailable
        }
        return value
    }

    private static func text(
        _ document: LegalDocument,
        in bundle: Bundle,
        directory: String
    ) throws -> String? {
        guard let url = bundle.url(
            forResource: document.rawValue,
            withExtension: "txt",
            subdirectory: directory
        ) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
