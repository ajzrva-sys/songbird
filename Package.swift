// swift-tools-version: 5.9
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let flacVendor = packageRoot + "/Vendor/FLAC"
let aubioVendor = packageRoot + "/Vendor/aubio"

let package = Package(
    name: "Songbird",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SongbirdLib", targets: ["SongbirdLib"]),
        .library(
            name: "SongbirdDockTilePlugin",
            type: .dynamic,
            targets: ["SongbirdDockTilePlugin"]
        ),
        .executable(name: "Songbird", targets: ["Songbird"]),
        .executable(name: "CDSandboxProbe", targets: ["CDSandboxProbe"]),
        .executable(
            name: "SongbirdUsabilityFixture",
            targets: ["SongbirdUsabilityFixture"]
        ),
        .executable(name: "SongbirdUIProbe", targets: ["SongbirdUIProbe"]),
        .executable(
            name: "SongbirdLibraryRemediator",
            targets: ["SongbirdLibraryRemediator"]
        ),
    ],
    dependencies: [
        ProcessInfo.processInfo.environment["SONGBIRD_OFFLINE_DEPS"] == "1"
            ? .package(path: "Vendor/GRDB.swift")
            : .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .target(
            name: "AudioAtomics",
            path: "Sources/AudioAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OpticalDiscBridge",
            path: "Sources/OpticalDiscBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "FLACBridge",
            path: "Sources/FLACBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "\(flacVendor)/libFLAC.14.dylib",
                    "\(flacVendor)/libogg.0.dylib",
                    "-Xlinker", "-rpath", "-Xlinker", flacVendor,
                ], .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "AubioBridge",
            path: "Sources/AubioBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "\(aubioVendor)/libaubio.5.dylib",
                    "-Xlinker", "-rpath", "-Xlinker", aubioVendor,
                ], .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "SongbirdDockIconSupport",
            path: "Sources/DockIconSupport",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .target(
            name: "SongbirdDockTilePlugin",
            dependencies: ["SongbirdDockIconSupport"],
            path: "Sources/DockTilePlugin",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .target(
            name: "SongbirdLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "FLACBridge",
                "AubioBridge",
                "AudioAtomics",
                "OpticalDiscBridge",
                "SongbirdDockIconSupport",
            ],
            path: "Sources",
            exclude: [
                "App",
                "FLACBridge",
                "AubioBridge",
                "AudioAtomics",
                "OpticalDiscBridge",
                "CDSandboxProbe",
                "DockIconSupport",
                "DockTilePlugin",
            ],
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "Songbird",
            dependencies: ["SongbirdLib"],
            path: "Sources/App",
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            ], .when(platforms: [.macOS]))]
        ),
        .executableTarget(
            name: "CDSandboxProbe",
            dependencies: ["OpticalDiscBridge"],
            path: "Sources/CDSandboxProbe"
        ),
        .target(
            name: "SongbirdUsabilityFixtureSupport",
            dependencies: ["SongbirdLib"],
            path: "Tools/SongbirdUsabilityFixture/Support"
        ),
        .executableTarget(
            name: "SongbirdUsabilityFixture",
            dependencies: ["SongbirdUsabilityFixtureSupport"],
            path: "Tools/SongbirdUsabilityFixture/Command",
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            ], .when(platforms: [.macOS]))]
        ),
        .executableTarget(
            name: "SongbirdUIProbe",
            path: "Tools/SongbirdUIProbe",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .executableTarget(
            name: "SongbirdLibraryRemediator",
            dependencies: ["SongbirdLib"],
            path: "Tools/SongbirdLibraryRemediator",
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            ], .when(platforms: [.macOS]))]
        ),
        .testTarget(
            name: "SongbirdTests",
            dependencies: [
                "SongbirdLib",
                "SongbirdDockIconSupport",
                "SongbirdUsabilityFixtureSupport",
            ]
        ),
    ]
)
