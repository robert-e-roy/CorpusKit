# CorpusKit Quick Reference

## Basic Setup

```swift
import CorpusKit

// One-time initialization
let embeddingService = EmbeddingService()
try await embeddingService.load()

let vectorStore = VectorStore<Chunk>()
vectorStore.build(items: chunks, embeddings: precomputedEmbeddings)
```

## Generate Embeddings

```swift
// Single embedding
let query = "What is the meaning of life?"
let embedding = try await embeddingService.embed(query)
// Returns: [Float] of length 384, L2-normalized

// Batch with progress
let texts = ["query 1", "query 2", "query 3"]
let embeddings = try await embeddingService.embedBatch(texts) { progress in
    print("Progress: \(Int(progress * 100))%")
}
```

## Vector Search

### Simple search (no weighting)
```swift
let results = vectorStore.search(query: queryEmbedding, k: 5)

for result in results {
    print("\(result.item.text)")
    print("Score: \(result.rawScore)")
}
```

### Search with custom weighting
```swift
let results = vectorStore.search(
    query: queryEmbedding,
    k: 5,
    weightFunction: { chunk in
        // Your custom weighting logic
        chunk.importance * 1.5
    }
)
```

### Complex weighting example
```swift
let chapterWeights: [String: Float] = [
    "How It Works": 1.2,
    "Into Action": 1.2,
    // ... more chapters
]

let results = vectorStore.search(
    query: queryEmbedding,
    k: 5,
    weightFunction: { chunk in
        let chapterWeight = chapterWeights[chunk.chapter] ?? 0.75
        let importance = max(chunk.importance, 0.1)
        return chapterWeight * importance
    }
)
```

## Working with Results

```swift
// ScoredChunk structure
struct ScoredChunk<T> {
    let item: T           // Your chunk/item
    let rawScore: Float   // Cosine similarity (0.0 to 1.0)
    let weightedScore: Float  // After applying weight function
}

// Access results
for (index, result) in results.enumerated() {
    print("Rank \(index + 1):")
    print("  Text: \(result.item.text)")
    print("  Raw: \(result.rawScore)")
    print("  Weighted: \(result.weightedScore)")
}
```

## Common Patterns

### CorpusKitStudio Pattern (Observable wrapper)

```swift
import CorpusKit
import Observation

@Observable
class EmbeddingServiceWrapper {
    var isLoaded = false
    var progress: Double = 0
    private let service = EmbeddingService()

    func load() async throws {
        try await service.load()
        await MainActor.run { isLoaded = true }
    }

    func embed(_ text: String) async throws -> [Float] {
        return try await service.embed(text)
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        return try await service.embedBatch(texts) { progress in
            await MainActor.run { self.progress = progress }
        }
    }
}
```

### BigBookViaLLM Pattern (Adapter for legacy API)

```swift
import CorpusKit

class VectorStoreAdapter {
    private let store = VectorStore<Chunk>()
    private var meta: CorpusMeta?

    func load(corpus: LoadedCorpus) {
        self.meta = corpus.meta
        store.build(items: corpus.chunks, embeddings: corpus.embeddings)
    }

    func search(queryEmbedding: [Float], k: Int) -> [Chunk] {
        let results = store.search(
            query: queryEmbedding,
            k: k,
            weightFunction: { [weak self] chunk in
                self?.meta?.chapterWeight(for: chunk.chapter) ?? 0.75
            }
        )
        return results.map { $0.item }
    }
}
```

## Error Handling

```swift
do {
    try await embeddingService.load()
} catch EmbeddingService.EmbeddingError.modelNotFound {
    print("MiniLMEmbedding.mlpackage not found in bundle")
} catch EmbeddingService.EmbeddingError.vocabNotFound {
    print("vocab.json or vocab.txt not found in bundle")
} catch {
    print("Unexpected error: \(error)")
}
```

## Performance Tips

1. **Load model once** at app startup, reuse for all embeddings
2. **Batch processing** - use `embedBatch()` for multiple texts
3. **Pre-compute embeddings** - VectorStore expects pre-computed embeddings
4. **Keep results small** - use `k` parameter to limit results
5. **Weight functions** - keep weight calculations simple and fast

## Common Chunk Models

### CorpusKitStudio
```swift
struct Chunk {
    let id: Int
    var text: String
    let source: String
    var chapter: String
    var page: Int
    var importance: Float
    var corpusAuthority: Float
    var usageScore: Float?
    var embedding: [Float]?
}
```

### BigBookViaLLM
```swift
struct Chunk {
    let id: Int
    let text: String
    let source: String
    var chapter: String
    let page: Int
    var displayText: String?
}
```

### Minimal Example
```swift
struct Chunk {
    let id: Int
    let text: String
}
```

## Debugging

### Check embedding normalization
```swift
let embedding = try await embeddingService.embed("test")
let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
print("Magnitude: \(magnitude)")  // Should be ≈ 1.0
```

### Compare search scores
```swift
let results = vectorStore.search(query: query, k: 10)
for result in results {
    print("Raw: \(result.rawScore), Weighted: \(result.weightedScore)")
}
```

### Verify embeddings are unique
```swift
vectorStore.build(items: chunks, embeddings: embeddings)
// Check first few embeddings are different
print("Embedding[0] prefix: \(embeddings[0].prefix(5))")
print("Embedding[1] prefix: \(embeddings[1].prefix(5))")
```

## Resources

- **README.md** - Overview and installation
- **INTEGRATION.md** - Step-by-step migration guide
- **DIFFERENCES.md** - Implementation differences analysis
- **MIGRATION_CHECKLIST.md** - Detailed migration checklist
