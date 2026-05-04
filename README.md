# CorpusKit

Shared Swift Package for embedding and vector similarity search functionality used by:
- **CorpusKitStudio** (macOS) - Corpus authoring and testing tool
- **BigBookViaLLM** (iOS) - On-device RAG application

## Features

### EmbeddingService
- On-device embedding generation using MiniLM-L6-v2 (CoreML)
- L2-normalized 384-dimensional vectors
- WordPiece tokenization with BERT vocabulary
- Batch processing with progress callbacks
- Supports both `.json` and `.txt` vocabulary formats

### VectorStore
- Fast cosine similarity search using Accelerate framework's vDSP
- Generic over item types for flexibility
- Pre-computed embeddings (no re-embedding at query time)
- Optional custom weighting functions per item
- Returns scored results with both raw and weighted scores

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Adding to an Xcode Project

1. In Xcode, select your project in the navigator
2. Select your app target
3. Go to the "General" tab, scroll to "Frameworks, Libraries, and Embedded Content"
4. Click the "+" button
5. Click "Add Other..." → "Add Package Dependency..."
6. Enter the local path: `../CorpusKit`
7. Click "Add Package"
8. Select "CorpusKit" library and click "Add Package"

### Required Resources

Both apps using CorpusKit must include these resources in their bundle:

1. **MiniLMEmbedding.mlpackage** - CoreML model
2. **vocab.json** or **vocab.txt** - BERT WordPiece vocabulary

## Usage

### EmbeddingService

```swift
import CorpusKit

let embeddingService = EmbeddingService()

// Load model (one time, at app startup)
try await embeddingService.load()

// Generate embedding for a query
let embedding = try await embeddingService.embed("What is the meaning of life?")
// Returns: [Float] of length 384, L2-normalized

// Batch processing with progress
let texts = ["query 1", "query 2", "query 3"]
let embeddings = try await embeddingService.embedBatch(texts) { progress in
    print("Progress: \(progress * 100)%")
}
```

### VectorStore

```swift
import CorpusKit

struct Chunk {
    let id: Int
    let text: String
    let chapter: String
    let importance: Float
}

// Create and build index
let store = VectorStore<Chunk>()
store.build(items: chunks, embeddings: precomputedEmbeddings)

// Search with custom weighting
let results = store.search(
    query: queryEmbedding,
    k: 5,
    weightFunction: { chunk in
        // Example: boost important chunks
        chunk.importance * 1.5
    }
)

// Access results
for result in results {
    print("Chunk: \(result.item.text)")
    print("Raw score: \(result.rawScore)")
    print("Weighted score: \(result.weightedScore)")
}
```

## Architecture Notes

### Key Differences from Original Implementations

**EmbeddingService:**
- Unified model loading (supports both generic MLModel and typed models)
- Supports both vocab.json and vocab.txt formats
- Consistent async/await API
- L2 normalization using vDSP for performance

**VectorStore:**
- Generic over item type (not tied to specific Chunk model)
- Simplified API with optional weight functions
- Returns structured ScoredChunk results
- Apps maintain their own chunk models and weighting logic

### Migration Strategy

Both apps should:
1. Add CorpusKit as a local package dependency
2. Update imports from old service classes to `import CorpusKit`
3. Replace `VectorIndex` with `VectorStore<Chunk>`
4. Adapt weight calculation to use the `weightFunction` parameter
5. Delete the old `EmbeddingService.swift`, `VectorIndex.swift`, and `WordPieceTokenizer.swift` files

## Testing

```bash
cd CorpusKit
swift test
```

## License

Same license as parent projects (CorpusKitStudio and BigBookViaLLM).
