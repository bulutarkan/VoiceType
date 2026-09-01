// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceType",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceType",
            path: "Sources/VoiceType",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        )
    ]
)
