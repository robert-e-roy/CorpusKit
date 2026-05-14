//
//  VectorIndex.swift
//  CorpusKit
//
//  Wrapper around CorpusKit's VectorStore for generic corpus retrieval
//

import Foundation

public class VectorIndex {

    private let store = VectorStore<Chunk>()
    public let dimension = 384

    public init() {}

    public func build(chunks: [Chunk]) {
        let embeddings = chunks.compactMap { $0.embedding }
        store.build(items: chunks, embeddings: embeddings)
    }

    /// Search using cosine similarity with chunk importance weighting
    public func search(
        query: [Float],
        k: Int = 3
    ) -> [(chunk: Chunk, rawScore: Float, chunkWeight: Float, finalScore: Float)] {

        // Apply weight function based on chunk's importance field
        let results = store.search(
            query: query,
            k: k,
            weightFunction: { chunk in
                chunk.importance  // Use chunk's importance value directly (0.0-1.0)
            }
        )

        // Map results to include raw score, weight, and final score
        let mappedResults = results.map { result -> (chunk: Chunk, rawScore: Float, chunkWeight: Float, finalScore: Float) in
            let weight = result.item.importance
            let rawScore = result.rawScore
            let finalScore = rawScore * weight  // Final score is raw cosine * importance weight
            return (chunk: result.item, rawScore: rawScore, chunkWeight: weight, finalScore: finalScore)
        }

        #if DEBUG
        // Log first 5 results before and after weight is applied
        let top5 = Array(mappedResults.prefix(5))
        if !top5.isEmpty {
            print("\n📊 Search Results (top \(top5.count)):")
            for result in top5 {
                print("  chunk: \(result.chunk.chapter) p.\(result.chunk.page)")
                print("    raw cosine: \(String(format: "%.4f", result.rawScore))")
                print("    importance weight: \(String(format: "%.2f", result.chunkWeight))")
                print("    final score: \(String(format: "%.4f", result.finalScore))")
            }
        }
        #endif

        return mappedResults
    }
}
