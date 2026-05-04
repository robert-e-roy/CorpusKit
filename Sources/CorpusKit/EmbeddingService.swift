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
    public let dimension = 384

    public init() {}

    /// Load the MiniLM embedding model from the app bundle
    /// - Throws: EmbeddingError if model or vocabulary cannot be loaded
    public func load() async throws {
        // Try multiple possible locations for the model
        var modelURL: URL?

        // 1. Try as .mlpackage (source)
        modelURL = Bundle.main.url(forResource: "MiniLMEmbedding", withExtension: "mlpackage")

        // 2. Try as .mlmodelc (compiled)
        if modelURL == nil {
            modelURL = Bundle.main.url(forResource: "MiniLMEmbedding", withExtension: "mlmodelc")
        }

        // 3. Try searching in Resources directory directly
        if modelURL == nil, let resourcesURL = Bundle.main.resourceURL {
            let mlpackageURL = resourcesURL.appendingPathComponent("MiniLMEmbedding.mlpackage")
            let mlmodelcURL = resourcesURL.appendingPathComponent("MiniLMEmbedding.mlmodelc")

            if FileManager.default.fileExists(atPath: mlpackageURL.path) {
                modelURL = mlpackageURL
            } else if FileManager.default.fileExists(atPath: mlmodelcURL.path) {
                modelURL = mlmodelcURL
            }
        }

        guard let finalURL = modelURL else {
            throw EmbeddingError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        model = try await MLModel.load(contentsOf: finalURL, configuration: config)

        // Load tokenizer - try both .json and .txt formats
        var vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "json")
        if vocabURL == nil {
            vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt")
        }

        guard let finalVocabURL = vocabURL else {
            throw EmbeddingError.vocabNotFound
        }

        tokenizer = try WordPieceTokenizer(vocabURL: finalVocabURL)

        // Run diagnostic to verify embeddings are working correctly
        #if DEBUG
        try await runEmbeddingDiagnostic()
        #endif
    }

    public var isLoaded: Bool {
        model != nil && tokenizer != nil
    }

    /// Diagnostic test to verify embeddings produce different vectors for different text
    /// This catches issues where the model silently degrades to producing identical vectors
    private func runEmbeddingDiagnostic() async throws {
        print("\n🔍 EMBEDDING DIAGNOSTIC")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let testPhrases = [
            "we admitted we were powerless over alcohol",
            "the quick brown fox jumps over the lazy dog",
            "resentment is the number one offender"
        ]

        var embeddings: [[Float]] = []

        for phrase in testPhrases {
            print("\n📊 Input: '\(phrase.prefix(40))...'")

            // Show tokenization
            guard let tokenizer = tokenizer else {
                print("   ⚠️  Tokenizer not loaded!")
                continue
            }
            let (ids, mask) = tokenizer.tokenize(phrase, maxLength: 128)
            print("   Token IDs (first 20): \(ids.prefix(20))")
            print("   Attention mask (first 20): \(mask.prefix(20))")
            print("   Token count: \(ids.count)")

            // Generate embedding
            let v = try await embed(phrase)
            let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
            let first5 = v.prefix(5).map { String(format: "%.4f", $0) }
            let last5 = v.suffix(5).map { String(format: "%.4f", $0) }
            print("   Embedding magnitude: \(String(format: "%.6f", mag))")
            print("   First 5 values: [\(first5.joined(separator: ", "))]")
            print("   Last 5 values: [\(last5.joined(separator: ", "))]")
            embeddings.append(v)
        }

        // Check cross-similarities between unrelated phrases
        print("\n🔬 Cross-similarity between unrelated phrases:")
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

                print("   \(label): \(String(format: "%.4f", dot))")

                if dot > 0.5 {
                    print("   ⚠️  WARNING: Similarity \(String(format: "%.4f", dot)) is too high for unrelated text!")
                    print("   ⚠️  Embedding model may be broken or degrading to similar vectors")
                    print("   ⚠️  Expected: < 0.3 for unrelated sentences")
                }
            }
        }

        // Summary
        print("\n📋 DIAGNOSTIC SUMMARY:")
        print("   ✓ All magnitudes should be ~1.0 (L2 normalized)")
        print("   ✓ Cross-similarities should be < 0.3 for unrelated text")
        print("   ✓ Token IDs should be different for different phrases")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }

    /// Generate L2-normalized embedding for the given text
    /// - Parameter text: Input text to embed
    /// - Returns: 384-dimensional L2-normalized embedding vector
    /// - Throws: EmbeddingError if model is not loaded or inference fails
    public func embed(_ text: String) async throws -> [Float] {
        guard let model = model, let tokenizer = tokenizer else {
            throw EmbeddingError.notLoaded
        }

        // Tokenize
        let (ids, mask) = tokenizer.tokenize(text, maxLength: 128)

        // Create MLMultiArray inputs
        let inputIds = try createMLMultiArray(from: ids)
        let attentionMask = try createMLMultiArray(from: mask)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIds,
            "attention_mask": attentionMask
        ])

        let output = try await model.prediction(from: input)

        // IMPORTANT: MiniLM-L6-v2 uses MEAN POOLING (not CLS pooling)
        // The pre-pooled output "var_548" may include padding tokens incorrectly
        // We must do mean pooling ourselves with proper attention mask

        #if DEBUG
        // Log which output path we're using (first embed only)
        struct OutputLogger {
            static var hasLogged = false
        }
        if !OutputLogger.hasLogged {
            OutputLogger.hasLogged = true
            print("\n🔬 MODEL OUTPUT INSPECTION:")
            print("   Available outputs: \(output.featureNames)")
            if let pooled = output.featureValue(for: "var_548")?.multiArrayValue {
                print("   var_548 shape: \(pooled.shape)")
            }
            if let hidden = output.featureValue(for: "hidden_states")?.multiArrayValue {
                print("   hidden_states shape: \(hidden.shape)")
            }
            if let hidden = output.featureValue(for: "last_hidden_state")?.multiArrayValue {
                print("   last_hidden_state shape: \(hidden.shape)")
            }
        }
        #endif

        // Extract hidden states and mean pool with attention mask
        if let hiddenStates = output.featureValue(for: "hidden_states")?.multiArrayValue {
            return meanPool(hiddenStates, mask: mask)
        }

        // Try alternate name for hidden states
        if let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue {
            return meanPool(hiddenState, mask: mask)
        }

        // Only use pre-pooled output as last resort (may be incorrectly pooled)
        if let pooledOutput = output.featureValue(for: "var_548")?.multiArrayValue {
            print("⚠️  WARNING: Using pre-pooled output var_548 - may include padding tokens!")
            return extractEmbedding(from: pooledOutput)
        }

        throw EmbeddingError.badOutput
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

    /// Extract embedding from already-pooled output (shape: [1, 384])
    private func extractEmbedding(from array: MLMultiArray) -> [Float] {
        let dimension = array.shape[1].intValue
        var embedding = [Float](repeating: 0, count: dimension)

        for i in 0..<dimension {
            embedding[i] = array[[0, NSNumber(value: i)]].floatValue
        }

        return l2Normalize(embedding)
    }

    /// Mean pooling over token dimension (shape: [1, 128, 384])
    /// Only averages non-padding tokens (where mask[i] == 1)
    private func meanPool(_ array: MLMultiArray, mask: [Int]) -> [Float] {
        let seqLen = array.shape[1].intValue
        let hiddenSize = array.shape[2].intValue
        var pooled = [Float](repeating: 0, count: hiddenSize)
        var count: Float = 0

        #if DEBUG
        let activeTokens = mask.prefix(seqLen).filter { $0 == 1 }.count
        let paddingTokens = mask.prefix(seqLen).filter { $0 == 0 }.count

        // Log pooling details for first call only
        struct PoolingLogger {
            static var hasLogged = false
        }
        if !PoolingLogger.hasLogged {
            PoolingLogger.hasLogged = true
            print("\n🔬 MEAN POOLING INSPECTION:")
            print("   Sequence length: \(seqLen)")
            print("   Hidden size: \(hiddenSize)")
            print("   Active tokens (mask=1): \(activeTokens)")
            print("   Padding tokens (mask=0): \(paddingTokens)")
            print("   Mask (first 20): \(mask.prefix(20))")
        }
        #endif

        for t in 0..<min(seqLen, mask.count) {
            guard mask[t] == 1 else { continue }  // Skip padding tokens
            for h in 0..<hiddenSize {
                let idx = t * hiddenSize + h
                pooled[h] += array[idx].floatValue
            }
            count += 1
        }

        if count > 0 {
            pooled = pooled.map { $0 / count }
        }

        #if DEBUG
        if !PoolingLogger.hasLogged {
            print("   Tokens averaged: \(Int(count))")
        }
        #endif

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
                MiniLM embedding model not found.

                Please ensure MiniLMEmbedding.mlpackage is added to the project:
                1. Download the all-MiniLM-L6-v2 model
                2. Convert to Core ML format (.mlpackage)
                3. Add to app Resources/
                4. Ensure it's included in the target's "Copy Bundle Resources"
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
