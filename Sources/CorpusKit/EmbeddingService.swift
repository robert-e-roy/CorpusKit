//
//  EmbeddingService.swift
//  CorpusKit
//
//  Shared embedding service for MiniLM-L6-v2 model
//  Uses Apple's CoreML for on-device inference
//

import CoreML
import Accelerate
import Foundation

/// Service for generating L2-normalized embeddings using MiniLM-L6-v2 model
public class EmbeddingService {

    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?
    public let dimension = EmbeddingModelInfo.current.dimension
    /// Fixed input length the bundled model was traced at; read from model metadata at load,
    /// falling back to the value declared in `EmbeddingModelInfo`. Never hardcoded.
    private var sequenceLength = EmbeddingModelInfo.current.seqLength

    public init() {}

    /// Load the MiniLM embedding model from the app bundle
    /// - Throws: EmbeddingError if model or vocabulary cannot be loaded
    public func load() async throws {
        // Resolve the model + vocab. Prefer the package's own bundled resources (Bundle.module),
        // so every consumer shares one model; fall back to the app bundle (Bundle.main) for apps
        // that still ship their own copy during migration.
        // Prefer the precompiled .mlmodelc (shipped in the package); .mlpackage is only loadable
        // when a host app's Xcode build compiled it (Bundle.main fallback during migration).
        guard let modelURL = Self.resourceURL(named: "arctic-embed-m-v1.5", extensions: ["mlmodelc", "mlpackage"]) else {
            throw EmbeddingError.modelNotFound
        }

        let config = MLModelConfiguration()
        // Force CPU (FP32) for cross-platform determinism. Retrieval requires the query and the
        // stored corpus embeddings to come from the *same* compute path; .cpuAndNeuralEngine lets
        // each device pick a different backend (e.g. iPhone Neural Engine FP16 vs Mac CPU/GPU),
        // which shifts the query vector and breaks ranking on one platform. CPU FP32 is identical
        // across devices. Embedding one query is fast; corpus generation is a one-time build cost.
        config.computeUnits = .cpuOnly
        let loadedModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
        model = loadedModel

        // Read the fixed sequence length from the model's user-defined metadata
        // (coremltools writes it under the creator-defined key), fall back to the declared value.
        if let creatorMeta = loadedModel.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
           let seqStr = creatorMeta["seq_length"], let seq = Int(seqStr) {
            sequenceLength = seq
        }

        // Load tokenizer - try both .json and .txt formats
        guard let vocabURL = Self.resourceURL(named: "vocab", extensions: ["json", "txt"]) else {
            throw EmbeddingError.vocabNotFound
        }

        tokenizer = try WordPieceTokenizer(vocabURL: vocabURL)

        // Run diagnostic to verify embeddings are working correctly
        #if DEBUG
        try await runEmbeddingDiagnostic()
        #endif
    }

    /// Locate a bundled resource, preferring the package's own bundle (`Bundle.module`) and
    /// falling back to the app bundle (`Bundle.main`). Tries each extension in order.
    private static func resourceURL(named name: String, extensions: [String]) -> URL? {
        for bundle in [Bundle.module, Bundle.main] {
            for ext in extensions {
                if let url = bundle.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
            // Some build layouts place resources flat in the bundle root.
            if let resourcesURL = bundle.resourceURL {
                for ext in extensions {
                    let candidate = resourcesURL.appendingPathComponent("\(name).\(ext)")
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    public var isLoaded: Bool {
        model != nil && tokenizer != nil
    }

    /// Diagnostic test to verify embeddings produce different vectors for different text
    /// This catches issues where the model silently degrades to producing identical vectors
    private func runEmbeddingDiagnostic() async throws {
        dlog("\n🔍 EMBEDDING DIAGNOSTIC")
        dlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let testPhrases = [
            "we admitted we were powerless over alcohol",
            "the quick brown fox jumps over the lazy dog",
            "resentment is the number one offender"
        ]

        var embeddings: [[Float]] = []

        for phrase in testPhrases {
            dlog("\n📊 Input: '\(phrase.prefix(40))...'")

            // Show tokenization
            guard let tokenizer = tokenizer else {
                dlog("   ⚠️  Tokenizer not loaded!")
                continue
            }
            let (ids, mask) = tokenizer.tokenize(phrase, maxLength: 128)
            dlog("   Token IDs (first 20): \(ids.prefix(20))")
            dlog("   Attention mask (first 20): \(mask.prefix(20))")
            dlog("   Token count: \(ids.count)")

            // Generate embedding
            let v = try await embed(phrase)
            let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
            let first5 = v.prefix(5).map { String(format: "%.4f", $0) }
            let last5 = v.suffix(5).map { String(format: "%.4f", $0) }
            dlog("   Embedding magnitude: \(String(format: "%.6f", mag))")
            dlog("   First 5 values: [\(first5.joined(separator: ", "))]")
            dlog("   Last 5 values: [\(last5.joined(separator: ", "))]")
            embeddings.append(v)
        }

        // Check cross-similarities between unrelated phrases
        dlog("\n🔬 Cross-similarity between unrelated phrases:")
        for i in 0..<embeddings.count {
            for j in (i+1)..<embeddings.count {
                var dot: Float = 0
                vDSP_dotpr(embeddings[i], 1, embeddings[j], 1, &dot, vDSP_Length(embeddings[i].count))

                let label: String
                if i == 0 && j == 1 {
                    label = "alcohol vs fox"
                } else if i == 0 && j == 2 {
                    label = "alcohol vs resentment"
                } else {
                    label = "fox vs resentment"
                }

                dlog("   \(label): \(String(format: "%.4f", dot))")

                if dot > 0.5 {
                    dlog("   ⚠️  WARNING: Similarity \(String(format: "%.4f", dot)) is too high for unrelated text!")
                    dlog("   ⚠️  Embedding model may be broken or degrading to similar vectors")
                    dlog("   ⚠️  Expected: < 0.3 for unrelated sentences")
                }
            }
        }

        // Summary
        dlog("\n📋 DIAGNOSTIC SUMMARY:")
        dlog("   ✓ All magnitudes should be ~1.0 (L2 normalized)")
        dlog("   ✓ Cross-similarities should be < 0.3 for unrelated text")
        dlog("   ✓ Token IDs should be different for different phrases")
        dlog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    /// Generate L2-normalized embedding for the given text
    /// - Parameter text: Input text to embed
    /// - Returns: 384-dimensional L2-normalized embedding vector
    /// - Throws: EmbeddingError if model is not loaded or inference fails
    public func embed(_ text: String) async throws -> [Float] {
        guard let model = model, let tokenizer = tokenizer else {
            throw EmbeddingError.notLoaded
        }

        // Tokenize to the model's fixed input length.
        let (ids, mask) = tokenizer.tokenize(text, maxLength: sequenceLength)

        // Create MLMultiArray inputs (the model declares Float32 inputs of shape [1, seqLength]).
        let inputIds = try createMLMultiArray(from: ids)
        let attentionMask = try createMLMultiArray(from: mask)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIds,
            "attention_mask": attentionMask
        ])

        let output = try await model.prediction(from: input)

        // The model emits token embeddings (last_hidden_state, shape [1, seq, 768]). Pool them
        // here with the attention mask, then L2-normalize. Pooling is done client-side because
        // coremltools (neuralnetwork) mis-converts in-graph masked-mean reduce ops, collapsing
        // all inputs to ~one vector — see Python Scripts/05_pytorch_to_coreml.py.
        guard let outputName = output.featureNames.first,
              let tokenEmbeddings = output.featureValue(for: outputName)?.multiArrayValue else {
            throw EmbeddingError.badOutput
        }
        return meanPool(tokenEmbeddings, mask: mask)
    }

    /// Generate embeddings for multiple texts with progress callback
    /// - Parameters:
    ///   - texts: Array of texts to embed
    ///   - onProgress: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: Array of L2-normalized embedding vectors
    public func embedBatch(
        _ texts: [String],
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for (i, text) in texts.enumerated() {
            // Cooperative cancellation: lets a caller stop a long batch (e.g. embedding a whole
            // book's chunks) between items. Throws CancellationError, which the caller can treat
            // as a clean abort since nothing is committed until the batch returns.
            try Task.checkCancellation()

            let embedding = try await embed(text)
            results.append(embedding)

            if let onProgress = onProgress {
                await MainActor.run {
                    onProgress(Double(i + 1) / Double(texts.count))
                }
            }
        }

        return results
    }

    // MARK: - Private Helpers

    private func createMLMultiArray(from values: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for (i, value) in values.enumerated() {
            array[[0, NSNumber(value: i)]] = NSNumber(value: value)
        }
        return array
    }

    /// Masked mean pooling over the token dimension of a [1, seq, hidden] output, then
    /// L2-normalize. Padding tokens (mask == 0) are excluded so they don't dominate the mean.
    private func meanPool(_ array: MLMultiArray, mask: [Int]) -> [Float] {
        let seqLen = array.shape[1].intValue
        let hiddenSize = array.shape[2].intValue
        var pooled = [Float](repeating: 0, count: hiddenSize)
        var count: Float = 0
        for t in 0..<min(seqLen, mask.count) where mask[t] == 1 {
            let base = t * hiddenSize
            for h in 0..<hiddenSize {
                pooled[h] += array[base + h].floatValue
            }
            count += 1
        }
        if count > 0 {
            for h in 0..<hiddenSize { pooled[h] /= count }
        }
        return l2Normalize(pooled)
    }

    /// L2-normalize vector using vDSP for performance
    private func l2Normalize(_ vec: [Float]) -> [Float] {
        var sumSq: Float = 0
        vDSP_svesq(vec, 1, &sumSq, vDSP_Length(vec.count))
        guard sumSq > 0 else { return vec }
        let norm = sqrt(sumSq)
        return vec.map { $0 / norm }
    }

    // MARK: - Error Types

    public enum EmbeddingError: Error, LocalizedError {
        case modelNotFound
        case vocabNotFound
        case notLoaded
        case badOutput
        case loadFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return """
                Embedding model not found.

                Expected arctic-embed-m-v1.5.mlmodelc bundled with the CorpusKit package.
                Regenerate it with Python Scripts/05_pytorch_to_coreml.py (mlprogram format) and
                copy it into CorpusKit/Sources/CorpusKit/Resources/.
                """
            case .vocabNotFound:
                return "Vocabulary file (vocab.json or vocab.txt) not found in app bundle"
            case .notLoaded:
                return "Embedding model not loaded. Call load() first."
            case .badOutput:
                return "Model produced invalid output. Check model format and inputs."
            case .loadFailed(let error):
                return "Failed to load embedding model: \(error.localizedDescription)"
            }
        }
    }
}
