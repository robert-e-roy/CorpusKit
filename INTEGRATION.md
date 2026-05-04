# CorpusKit Integration Guide

This guide explains how to integrate CorpusKit into both CorpusKitStudio (macOS) and BigBookViaLLM (iOS).

## Step 1: Add CorpusKit Package to Xcode Projects

### For CorpusKitStudio:

1. Open `CorpusKitStudio.xcodeproj` in Xcode
2. Select the project in the navigator (blue icon at the top)
3. Select the **CorpusKitStudio** target
4. Go to the **General** tab
5. Scroll to **Frameworks, Libraries, and Embedded Content**
6. Click the **+** button
7. Click **Add Other...** → **Add Package Dependency...**
8. In the search bar, enter the local path: `/Users/robroy/Projects/CorpusKit`
9. Click **Add Package**
10. Select **CorpusKit** library and click **Add Package**

### For BigBookViaLLM:

1. Open `BigBookViaLLM.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the **BigBookViaLLM** target
4. Go to the **General** tab
5. Scroll to **Frameworks, Libraries, and Embedded Content**
6. Click the **+** button
7. Click **Add Other...** → **Add Package Dependency...**
8. In the search bar, enter: `/Users/robroy/Projects/CorpusKit`
9. Click **Add Package**
10. Select **CorpusKit** library and click **Add Package**

## Step 2: Update CorpusKitStudio

### Update VectorIndex usage:

The old `VectorIndex` is now replaced with the generic `VectorStore<Chunk>`.

**Before:**
```swift
import Foundation

class VectorIndex {
    func build(chunks: [Chunk]) { ... }
    func search(query: [Float], k: Int, applyWeights: Bool) -> [(chunk: Chunk, rawScore: Float, weightedScore: Float)] { ... }
}
```

**After:**
```swift
import CorpusKit

// Create a weight function for chunks
func chunkWeight(_ chunk: Chunk) -> Float {
    let chapterWeights: [String: Float] = [
        "How It Works": 1.2,
        "Into Action": 1.2,
        "Working With Others": 1.1,
        // ... other chapter weights
    ]

    let corpusAuthority = chunk.corpusAuthority
    let chapterWeight = chapterWeights[chunk.chapter] ?? 0.75
    let chunkImportance = max(chunk.importance, 0.1)
    let usageSignal = chunk.usageScore ?? 1.0

    return corpusAuthority * chapterWeight * chunkImportance * usageSignal
}

// Build the vector store
let vectorStore = VectorStore<Chunk>()
vectorStore.build(items: chunks, embeddings: chunks.compactMap { $0.embedding })

// Search with weighting
let results = vectorStore.search(
    query: queryEmbedding,
    k: 3,
    weightFunction: chunkWeight
)

// Access results
for result in results {
    print("Chunk: \(result.item.text)")
    print("Raw score: \(result.rawScore)")
    print("Weighted score: \(result.weightedScore)")
}
```

### Update EmbeddingService:

**Before:**
```swift
import Observation

@Observable
class EmbeddingService {
    var isLoaded = false
    var progress: Double = 0
    // ...
}
```

**After:**
```swift
import CorpusKit
import Observation

// Create a wrapper to maintain @Observable behavior
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
            await MainActor.run {
                self.progress = progress
            }
        }
    }
}
```

## Step 3: Update BigBookViaLLM

### Update VectorStore usage:

**Before:**
```swift
class VectorStore {
    func load(corpus: CorpusLoader.LoadedCorpus) { ... }
    func search(queryEmbedding: [Float], k: Int) -> [Chunk] { ... }
}
```

**After:**
```swift
import CorpusKit

class VectorStoreAdapter {
    private let store = VectorStore<Chunk>()
    private var meta: CorpusMeta?

    func load(corpus: CorpusLoader.LoadedCorpus) {
        self.meta = corpus.meta
        store.build(items: corpus.chunks, embeddings: corpus.embeddings)
    }

    func search(queryEmbedding: [Float], k: Int) -> [Chunk] {
        let results = store.search(
            query: queryEmbedding,
            k: k,
            weightFunction: { [weak self] chunk in
                guard let self = self else { return 1.0 }
                return self.meta?.chapterWeight(for: chunk.chapter) ?? 0.75
            }
        )
        return results.map { $0.item }
    }
}
```

### Update EmbeddingService:

**Before:**
```swift
class EmbeddingService {
    func embed(_ text: String) async throws -> [Float] { ... }
}
```

**After:**
```swift
import CorpusKit

// The new EmbeddingService from CorpusKit is already async
// You can use it directly, or create an adapter if needed

let embeddingService = EmbeddingService()
try await embeddingService.load()
let embedding = try await embeddingService.embed("query text")
```

## Step 4: Delete Old Files

After verifying both apps build and work correctly, delete these files:

### In CorpusKitStudio/Pipeline/:
- ✅ `EmbeddingService.swift`
- ✅ `VectorIndex.swift`
- ✅ `WordPieceTokenizer.swift`

### In BigBookViaLLM/Engine/:
- ✅ `EmbeddingService.swift`
- ✅ `VectorStore.swift`

Note: Keep the WordPieceTokenizer in BigBookViaLLM only if it's being referenced elsewhere.

## Step 5: Test

### CorpusKitStudio:
1. Build the project (⌘B)
2. Run the app
3. Test embedding generation
4. Test vector search with a query
5. Verify chapter weighting is working correctly

### BigBookViaLLM:
1. Build the project (⌘B)
2. Run the app on simulator or device
3. Test corpus loading
4. Test query search
5. Verify results are ranked correctly

## Differences Between Implementations

### EmbeddingService:
- ✅ **Unified**: Now supports both vocab.json and vocab.txt
- ✅ **Consistent**: Uses async/await throughout
- ✅ **Performance**: L2 normalization using vDSP
- ⚠️ **Observable**: CorpusKitStudio needs a wrapper to maintain @Observable behavior

### VectorStore:
- ✅ **Generic**: Works with any item type
- ✅ **Flexible**: Custom weight functions per search
- ✅ **Clear API**: Returns structured ScoredChunk results
- ⚠️ **Migration**: Apps need to adapt their weight calculation logic

## Troubleshooting

### "No such module 'CorpusKit'"
- Ensure you added the package dependency correctly
- Clean build folder (⌘⇧K) and rebuild

### "Cannot find 'MiniLMEmbedding' in scope"
- The model is loaded dynamically via MLModel, not as a typed class
- Verify MiniLMEmbedding.mlpackage is in your app bundle

### "Vocabulary file not found"
- Ensure vocab.json or vocab.txt is in Copy Bundle Resources
- Check the file extension matches what's in your bundle

### Different search results after migration
- Verify embeddings are still L2-normalized
- Check that weight functions produce the same values as before
- Compare raw scores vs weighted scores in debug output
