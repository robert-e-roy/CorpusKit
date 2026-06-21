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

    // MARK: - Corpus bundle loading (Phase A2)

    /// The npy parser reads the exact format CorpusExporter writes (magic + v1 header + <f4 C-order).
    @Test func npyParsesFloat32MatrixRoundTrip() throws {
        let rows = 2, cols = 3
        let values: [[Float]] = [[0.1, -0.2, 0.3], [1.5, 2.5, -3.5]]

        // Build .npy byte-for-byte as CorpusExporter.encodeNpy does.
        let header = "{'descr': '<f4', 'fortran_order': False, 'shape': (\(rows), \(cols)), }"
        let padded = header.padding(toLength: ((header.count + 64) / 64) * 64 - 1, withPad: " ", startingAt: 0) + "\n"
        var data = Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, 0x01, 0x00])
        let hlen = UInt16(padded.utf8.count)
        data.append(UInt8(hlen & 0xFF)); data.append(UInt8((hlen >> 8) & 0xFF))
        data.append(contentsOf: padded.utf8)
        for row in values { for v in row { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } } }

        let parsed = try CorpusBundleLoader.parseNpyFloat32(data)
        #expect(parsed.count == rows)
        #expect(parsed[0].count == cols)
        for r in 0..<rows { for c in 0..<cols { #expect(abs(parsed[r][c] - values[r][c]) < 1e-6) } }
    }

    /// Catalog derives title/version from the `<Title>_v<N>` export convention (Phase A3).
    @Test func catalogParsesTitleAndVersionFromFilename() {
        let a = CorpusCatalog.titleAndVersion(fromFileName: "Big Book_v3")
        #expect(a.title == "Big Book")
        #expect(a.version == 3)
        let b = CorpusCatalog.titleAndVersion(fromFileName: "NoVersion")
        #expect(b.title == "NoVersion")
        #expect(b.version == nil)
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
