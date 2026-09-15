import Darwin
import Foundation
import SongbirdUsabilityFixtureSupport

@main
struct SongbirdUsabilityFixtureCommand {
    @MainActor
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showsHelp {
                print(Options.help)
                return
            }

            let seeder = try SongbirdUsabilityFixtureSeeder.fromEnvironment()
            if let bundleIdentifier = options.reportsStateForBundleIdentifier {
                let report = try seeder.stateReport(bundleIdentifier: bundleIdentifier)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
                return
            }
            let manifest: SongbirdUsabilityFixtureManifest
            if options.verifiesExistingFixture {
                manifest = try seeder.verify()
                print("Verified \(manifest.profile.rawValue) fixture at \(manifest.storePath)")
            } else {
                manifest = try seeder.seed(
                    profile: options.profile,
                    largeTrackCount: options.largeTrackCount
                )
                if let bundleIdentifier = options.defaultsBundleIdentifier {
                    try seeder.configureApplicationDefaults(
                        bundleIdentifier: bundleIdentifier,
                        manifest: manifest
                    )
                }
                print("Seeded \(manifest.profile.rawValue) fixture at \(manifest.storePath)")
            }
            print(
                "\(manifest.trackCount) tracks, \(manifest.albumCount) albums, "
                    + "\(manifest.playlistCount) playlists"
            )
            print("Manifest: \(seeder.manifestURL.path)")
        } catch {
            let message = "SongbirdUsabilityFixture: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}

private struct Options {
    var profile: SongbirdUsabilityFixtureProfile = .standard
    var largeTrackCount = SongbirdUsabilityFixtureSeeder.defaultLargeTrackCount
    var verifiesExistingFixture = false
    var defaultsBundleIdentifier: String?
    var reportsStateForBundleIdentifier: String?
    var showsHelp = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--profile":
                index += 1
                guard index < arguments.count,
                      let value = SongbirdUsabilityFixtureProfile(rawValue: arguments[index]) else {
                    throw CommandError.invalidProfile(index < arguments.count ? arguments[index] : nil)
                }
                profile = value
            case "--count":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]) else {
                    throw CommandError.invalidCount(index < arguments.count ? arguments[index] : nil)
                }
                largeTrackCount = value
            case "--verify":
                verifiesExistingFixture = true
            case "--configure-defaults":
                index += 1
                guard index < arguments.count, arguments[index].isEmpty == false else {
                    throw CommandError.missingValue("--configure-defaults")
                }
                defaultsBundleIdentifier = arguments[index]
            case "--report-state":
                index += 1
                guard index < arguments.count, arguments[index].isEmpty == false else {
                    throw CommandError.missingValue("--report-state")
                }
                reportsStateForBundleIdentifier = arguments[index]
            case "-h", "--help":
                showsHelp = true
            default:
                throw CommandError.unknownArgument(arguments[index])
            }
            index += 1
        }
    }

    static let help = """
    Seed an isolated Songbird library for AI-directed usability testing.

    SONGBIRD_UI_TEST_ROOT=/absolute/disposable/path swift run SongbirdUsabilityFixture [options]

      --profile empty|standard|health|large   Fixture profile (default: standard)
      --count N                       Track count for the large profile (default: 10000)
      --verify                         Verify an existing fixture without changing it
      --configure-defaults BUNDLE_ID  Seed disposable folder configuration preferences
      --report-state BUNDLE_ID        Print immutable current playlist/metadata/folder/media state
      -h, --help                       Show this help
    """
}

private enum CommandError: Error, LocalizedError {
    case invalidProfile(String?)
    case invalidCount(String?)
    case unknownArgument(String)
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let value):
            return "Invalid fixture profile \(value ?? "<missing>")."
        case .invalidCount(let value):
            return "Invalid fixture track count \(value ?? "<missing>")."
        case .unknownArgument(let value):
            return "Unknown argument \(value). Use --help for usage."
        case .missingValue(let option):
            return "Missing value after \(option)."
        }
    }
}
