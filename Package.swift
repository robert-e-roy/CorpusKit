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
    targets: [
        .target(
            name: "CorpusKit",
            dependencies: [],
            resources: [
                // Ship the precompiled model (.mlmodelc) — SPM .copy does not compile a raw
                // .mlmodel/.mlpackage, and Core ML's MLModel.load needs a compiled .mlmodelc.
                // Regenerate via Python Scripts/05_pytorch_to_coreml.py (neuralnetwork format).
                // .mlmodelc is a directory bundle — must be .copy (not .process).
                .copy("Resources/arctic-embed-m-v1.5.mlmodelc"),
                .copy("Resources/vocab.txt"),
            ]),
        .testTarget(
            name: "CorpusKitTests",
            dependencies: ["CorpusKit"]),
    ]
)
