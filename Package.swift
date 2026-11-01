// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MP3StreamDecoderKit",
    platforms: [.iOS("15.1"), .macOS(.v13)],
    products: [.library(name: "MP3StreamDecoderKit", targets: ["MP3StreamDecoderKit"])],
    targets: [
        .target(name: "MP3StreamDecoderKit"),
        .testTarget(
            name: "MP3StreamDecoderKitTests",
            dependencies: ["MP3StreamDecoderKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
