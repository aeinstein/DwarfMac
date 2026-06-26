// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DwarfMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        // VLCKit (libVLC) für RTSP-Wiedergabe — AVFoundation kann kein RTSP.
        .package(url: "https://github.com/tylerjonesio/vlckit-spm.git", from: "3.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DwarfMac",
            dependencies: [
                .product(name: "VLCKitSPM", package: "vlckit-spm"),
            ],
            path: "DwarfMac",
            exclude: [
                "Resources/Info.plist",
            ],
            resources: [
                .copy("Resources/astronomy_data.db"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
