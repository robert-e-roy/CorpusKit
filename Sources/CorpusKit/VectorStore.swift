//
//  VectorStore.swift
//  CorpusKit
//
//  Vector similarity search using vDSP for performance
//  Loads pre-computed embeddings and performs cosine similarity search
//

import Accelerate
import Foundation

/// Result of a vector similarity search with scoring details
public struct ScoredChunk<T> {
    public let item: T
    public let rawScore: Float
    public let weightedScore: Float

    public init(item: T, rawScore: Float, weightedScore: Float) {
        self.item = item
        self.rawScore = rawScore
        self.weightedScore = weightedScore
    }
}

/// Vector store for similarity search over pre-computed embeddings
/// Generic over the item type to support different chunk models
public class VectorStore<T> {

    private var items: [T] = []
    private var embeddings: [[Float]] = []
    public let dimension = 384

    public init() {}

    /// Build the vector index from items and their embeddings
    /// - Parameters:
    ///   - items: Array of items to index
    ///   - embeddings: Pre-computed L2-normalized embeddings matching items
    public func build(items: [T], embeddings: [[Float]]) {
        guard items.count == embeddings.count else {
            print("⚠️ VectorStore: item count (\(items.count)) != embedding count (\(embeddings.count))")
            return
        }

        self.items = items
        self.embeddings = embeddings
    }

    /// Search for similar items using cosine similarity (dot product of normalized vectors)
    /// - Parameters:
    ///   - query: L2-normalized query embedding vector
    ///   - k: Number of top results to return (default: 3)
    ///   - weightFunction: Optional function to compute weight for each item (default: 1.0)
    /// - Returns: Array of scored results sorted by weighted score (highest first)
    public func search(
        query: [Float],
        k: Int = 3,
        weightFunction: ((T) -> Float)? = nil
    ) -> [ScoredChunk<T>] {

        guard embeddings.count == items.count else { return [] }

        var scores: [(index: Int, rawScore: Float, weightedScore: Float)] = []
        scores.reserveCapacity(embeddings.count)

        for (i, embedding) in embeddings.enumerated() {
            // Compute cosine similarity via dot product (vectors are L2-normalized)
            var similarity: Float = 0
            vDSP_dotpr(
                query, 1,
                embedding, 1,
                &similarity,
                vDSP_Length(dimension)
            )

            let weight = weightFunction?(items[i]) ?? 1.0
            let weightedScore = similarity * weight

            scores.append((i, similarity, weightedScore))
        }

        return scores
            .sorted { $0.weightedScore > $1.weightedScore }
            .prefix(k)
            .map { ScoredChunk(item: items[$0.index], rawScore: $0.rawScore, weightedScore: $0.weightedScore) }
    }
}
