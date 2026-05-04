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

        // Create simple normalized embeddings (384 dimensions)
        let embeddings = [
            Array(repeating: Float(1.0 / sqrt(384.0)), count: 384), // All same values
            Array(repeating: Float(-1.0 / sqrt(384.0)), count: 384), // Negative values
            Array(repeating: Float(0.5 / sqrt(96.0)), count: 384)   // Mixed
        ]

        let store = VectorStore<TestItem>()
        store.build(items: items, embeddings: embeddings)

        // When: Searching with a query similar to first embedding
        let query = Array(repeating: Float(1.0 / sqrt(384.0)), count: 384)
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
        let embedding = Array(repeating: Float(1.0 / sqrt(384.0)), count: 384)
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
}
