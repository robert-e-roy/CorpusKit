//
//  CorpusKitTests.swift
//  CorpusKit
//

import Testing
import Foundation
@testable import CorpusKit

@Suite struct CorpusKitTests {

    @Test func vectorStoreBasicSearch() async throws {
        // Given: A simple vector store with 3 items
        struct TestItem {
            let id: Int
            let value: String
        }

        let items = [
            TestItem(id: 1, value: "first"),
            TestItem(id: 2, value: "second"),
            TestItem(id: 3, value: "third")
        ]

        // Create simple normalized embeddings at the model's dimension
        let dim = EmbeddingModelInfo.current.dimension
        let embeddings = [
            Array(repeating: Float(1.0 / sqrt(Double(dim))), count: dim),   // All same values
            Array(repeating: Float(-1.0 / sqrt(Double(dim))), count: dim),  // Negative values
            Array(repeating: Float(0.5 / sqrt(Double(dim) / 4)), count: dim) // Mixed
        ]

        let store = VectorStore<TestItem>()
        store.build(items: items, embeddings: embeddings)

        // When: Searching with a query similar to first embedding
        let query = Array(repeating: Float(1.0 / sqrt(Double(dim))), count: dim)
        let results = store.search(query: query, k: 2)

        // Then: Should return top 2 results
        #expect(results.count == 2)
        #expect(results[0].item.id == 1) // Most similar
    }

    @Test func vectorStoreWeightedSearch() async throws {
        struct WeightedItem {
            let id: Int
            let importance: Float
        }

        let items = [
            WeightedItem(id: 1, importance: 0.5),
            WeightedItem(id: 2, importance: 2.0), // High importance
            WeightedItem(id: 3, importance: 1.0)
        ]

        // All embeddings identical
        let dim = EmbeddingModelInfo.current.dimension
        let embedding = Array(repeating: Float(1.0 / sqrt(Double(dim))), count: dim)
        let embeddings = [embedding, embedding, embedding]

        let store = VectorStore<WeightedItem>()
        store.build(items: items, embeddings: embeddings)

        // Search with importance weighting
        let query = embedding
        let results = store.search(query: query, k: 3) { item in
            item.importance
        }

        // Should rank by importance since embeddings are identical
        #expect(results[0].item.id == 2) // Highest importance
        #expect(results[1].item.id == 3)
        #expect(results[2].item.id == 1) // Lowest importance
    }

    // MARK: - Embedding model bundled in the package (Phase 4a)

    /// The Arctic model + vocab ship as package resources, so EmbeddingService loads from
    /// Bundle.module without any host app. Verifies real on-device inference end to end.
    @Test func embeddingServiceLoadsBundledModelAndEmbeds() async throws {
        let service = EmbeddingService()
        try await service.load()
        #expect(service.isLoaded)

        let v = try await service.embed("Knowledge is power.")
        #expect(v.count == service.dimension)          // 768-dim (Arctic)
        #expect(v.count == EmbeddingModelInfo.current.dimension)
        #expect(v.contains { $0 != 0 })                 // not a zero vector

        // Model self-normalizes (L2): magnitude ~1.0
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.01)

        // Determinism: same text → identical vectors.
        let vAgain = try await service.embed("Knowledge is power.")
        #expect(v == vAgain)

        // Distinct text → distinct vectors (catches silent model degradation).
        let v2 = try await service.embed("The cat sat on the mat.")
        let dot = zip(v, v2).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        #expect(dot < 0.99)
    }

    /// Dimension + identity are sourced from EmbeddingModelInfo everywhere (Phase 4a-B).
    @Test func embeddingModelInfoIsSingleSourceOfDimension() {
        #expect(EmbeddingModelInfo.current.id == "Snowflake/snowflake-arctic-embed-m-v1.5")
        #expect(EmbeddingModelInfo.current.dimension == 768)
        #expect(EmbeddingModelInfo.current.seqLength == 256)
        #expect(EmbeddingService().dimension == EmbeddingModelInfo.current.dimension)
        #expect(VectorStore<Int>().dimension == EmbeddingModelInfo.current.dimension)
    }
}
