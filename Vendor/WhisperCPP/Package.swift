// swift-tools-version:5.9
// Thin SwiftPM wrapper around the official whisper.cpp xcframework.
//
// The binary is the `whisper-<build>-xcframework.zip` asset that ggml-org
// attaches to every whisper.cpp release; b5130 is the nightly cut at the
// v1.9.4 tag (2026-09-11). It ships libwhisper *and* libparakeet, so one
// ggml stack serves both the Whisper models and NVIDIA Parakeet TDT.
// SwiftWhisper (the previous dependency) pinned a 2023-era whisper.cpp with
// no Parakeet and no `whisper_full_params.suppress_nst`.
//
// To bump: download the new zip, run `swift package compute-checksum <zip>`,
// and update both the URL and the checksum below.
import PackageDescription

let package = Package(
    name: "WhisperCPP",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WhisperCPP", targets: ["whisper"]),
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5130/whisper-b5130-xcframework.zip",
            checksum: "033a43b0174e8cf9b366f72e4a428cdcf126f93ad1c87d3fa119a96bed6f231a"
        ),
    ]
)
