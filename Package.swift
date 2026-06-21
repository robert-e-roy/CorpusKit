// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CorpusKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CorpusKit",
            targets: ["CorpusKit"]),
    ],
    dependencies: [
        // Cross-platform (.corpus.zip) extraction — works on iOS + macOS (ditto/Process is
        // macOS-only). Relaxes the former zero-dependency principle so the bundle loader can be
        // a single shared cross-platform implementation. Matches the version BigBookViaLLM uses.
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
    ],
    targets: [
        .target(
            name: "CorpusKit",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                // Ship the precompiled model (.mlmodelc) — SPM .copy does not compile a raw
                // .mlmodel/.mlpackage, and Core ML's MLModel.load needs a compiled .mlmodelc.
                // Regenerate via Python Scripts/05_pytorch_to_coreml.py (mlprogram format).
                // .mlmodelc is a directory bundle — must be .copy (not .process).
                .copy("Resources/arctic-embed-m-v1.5.mlmodelc"),
                .copy("Resources/vocab.txt"),
            ]),
        .testTarget(
            name: "CorpusKitTests",
            dependencies: ["CorpusKit"]),
    ]
)
