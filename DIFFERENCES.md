# Implementation Differences Between Apps

This document details the differences found between CorpusKitStudio and BigBookViaLLM implementations before consolidation.

## EmbeddingService Differences

### Model Loading

**CorpusKitStudio:**
- Uses generic `MLModel` class
- Loads from Bundle with fallback search paths
- Configuration: `cpuAndNeuralEngine`
- Has `@Observable` wrapper with `isLoaded` and `progress` properties

**BigBookViaLLM:**
- Uses typed `MiniLMEmbedding` class (generated from .mlpackage)
- Direct typed model loading
- Configuration: `.all` (with commented out `.cpuOnly` for iPad)
- Simple class without observable behavior

**Resolution in CorpusKit:**
- Uses generic `MLModel` for compatibility with both approaches
- Apps can create their own `@Observable` wrappers if needed
- Configuration: `cpuAndNeuralEngine` (better default for both platforms)

### Tokenizer Integration

**CorpusKitStudio:**
- WordPieceTokenizer as separate class
- Vocab loaded from `vocab.json` (JSON dictionary format)
- Tokenizer created on-demand with try/catch fallback
- Has placeholder tokenizer fallback (hash-based) for development

**BigBookViaLLM:**
- WordPieceTokenizer embedded in same file
- Vocab loaded from `vocab.txt` (line-delimited format)
- Tokenizer created once during `load()`
- No fallback tokenizer

**Resolution in CorpusKit:**
- WordPieceTokenizer as separate file
- Supports both `.json` and `.txt` vocab formats
- Tokenizer created during `load()` with clear error if missing
- No fallback tokenizer (fail fast for production quality)

### Embedding Output Processing

**CorpusKitStudio:**
- Tries multiple output names: `var_548`, `hidden_states`, `last_hidden_state`
- Uses vDSP for L2 normalization (`vDSP_svesq`)
- Synchronous `embed()` method

**BigBookViaLLM:**
- Tries `var_548` (pooled output)
- Uses manual L2 normalization (map/reduce)
- Async `embed()` method
- Debug logging of magnitudes

**Resolution in CorpusKit:**
- Supports all three output names for compatibility
- Uses vDSP for performance (CorpusKitStudio approach)
- Async API throughout (BigBookViaLLM approach)
- No debug logging (apps can add their own wrappers)

### Batch Processing

**CorpusKitStudio:**
- `embedBatch()` with callback: `onProgress: @escaping (Double) -> Void`
- Updates progress via `MainActor.run`
- Returns `[[Float]]`

**BigBookViaLLM:**
- No batch processing method

**Resolution in CorpusKit:**
- Includes `embedBatch()` with optional callback
- Apps can use this for progress tracking if needed

## VectorStore/VectorIndex Differences

### Class Design

**CorpusKitStudio (VectorIndex):**
- Specific to `Chunk` type
- Stores chunks and embeddings separately
- Built-in chapter weights (hard-coded dictionary)
- `search()` returns tuple: `(chunk: Chunk, rawScore: Float, weightedScore: Float)`

**BigBookViaLLM (VectorStore):**
- Specific to `Chunk` type
- Stores chunks and embeddings separately
- Chapter weights from `CorpusMeta` (with fallback to legacy weights)
- `search()` returns `[Chunk]` (no scores exposed)
- Complex diagnostic logging
- NPY file loading for embeddings
- Corpus loading with filtering

**Resolution in CorpusKit:**
- **Generic** over item type `VectorStore<T>`
- Returns `ScoredChunk<T>` struct with both raw and weighted scores
- Weight function passed as parameter (not hard-coded)
- No corpus loading (apps handle their own data loading)
- No diagnostic logging (apps can add their own)

### Search Implementation

**CorpusKitStudio:**
```swift
func search(query: [Float], k: Int, applyWeights: Bool) -> [(chunk, raw, weighted)]
```
- Optional weight application via boolean flag
- Hard-coded chapter weights
- 4-factor weighting: corpusAuthority × chapterWeight × importance × usageScore

**BigBookViaLLM:**
```swift
func search(queryEmbedding: [Float], k: Int) -> [Chunk]
```
- Always applies chapter weights
- Weights from meta or fallback dictionary
- Simple weighting: similarity × chapterWeight

**Resolution in CorpusKit:**
```swift
func search(query: [Float], k: Int, weightFunction: ((T) -> Float)?) -> [ScoredChunk<T>]
```
- Weight function is optional closure
- Apps define their own weighting logic
- Returns structured results with both scores

### Chapter Weighting

**CorpusKitStudio:**
```swift
private static let chapterWeights: [String: Float] = [
    "How It Works": 1.2,
    "Into Action": 1.2,
    "Working With Others": 1.1,
    "There Is A Solution": 1.0,
    "More About Alcoholism": 1.0,
    "We Agnostics": 1.0,
    "A Vision For You": 1.0,
    "Our Southern Friend": 0.6,
]
```

**BigBookViaLLM:**
```swift
private static let chapterWeights: [String: Float] = [
    "How It Works": 1.2,
    "Into Action": 1.2,
    "Working With Others": 1.1,
    "There Is A Solution": 1.0,
    "More About Alcoholism": 1.0,
    "We Agnostics": 1.0,
    "A Vision For You": 1.0,
    "Bill'S Story": 1.0,           // Additional
    "The Doctor'S Opinion": 1.0,   // Additional
    "Foreword": 1.0,              // Additional
    "To Wives": 0.85,             // Additional
    "The Family Afterward": 0.85, // Additional
    "To Employers": 0.8,          // Additional
    "Our Southern Friend": 0.6,
]
```

**Resolution:**
- CorpusKit has no hard-coded weights
- Apps maintain their own weight dictionaries
- More flexible for different corpora

## Chunk Model Differences

**CorpusKitStudio:**
```swift
struct Chunk: Codable, Identifiable {
    let id: Int
    var text: String
    let source: String
    var chapter: String
    var page: Int
    var wordStart: Int
    var wordEnd: Int
    var importance: Float
    var corpusAuthority: Float
    var usageScore: Float?
    var embedding: [Float]?
}
```

**BigBookViaLLM:**
```swift
struct Chunk: Codable, Identifiable {
    let id: Int
    let text: String
    let source: String
    var chapter: String
    let page: Int
    var displayText: String?
}
```

**Resolution:**
- CorpusKit is generic over item type
- Apps keep their own `Chunk` models
- No shared chunk definition needed

## WordPieceTokenizer Differences

**CorpusKitStudio:**
- Vocabulary format: JSON (`{"token": id}`)
- Returns `(ids: [Int32], mask: [Int32])`
- Has extension on EmbeddingService for integration

**BigBookViaLLM:**
- Vocabulary format: TXT (line-delimited)
- Returns `(ids: [Int], mask: [Int])`
- Standalone class

**Resolution:**
- Supports both formats (auto-detect by file extension)
- Returns `(ids: [Int], mask: [Int])`
- Standalone class (no extension needed)

## Key Design Decisions

### 1. Generic VectorStore
**Rationale:** Both apps have different `Chunk` models. Making `VectorStore<T>` generic allows each app to use its own model without modification.

### 2. Weight Function Parameter
**Rationale:** Weighting logic differs significantly between apps. Passing it as a function parameter keeps the core search logic clean while allowing full customization.

### 3. No Data Loading in CorpusKit
**Rationale:** Apps have different data formats (JSON + NPY vs in-memory). Keep data loading in the apps, CorpusKit just does search.

### 4. Async-First API
**Rationale:** iOS/macOS best practices. CoreML model prediction can be async, so embrace it throughout.

### 5. No Observable in Core
**Rationale:** CorpusKitStudio needs `@Observable` for SwiftUI, but this couples the core logic to UI concerns. Apps can create wrappers.

### 6. Structured Results
**Rationale:** Exposing both raw and weighted scores helps with debugging and gives apps flexibility to use either.

## Migration Impact

### Low Risk:
- ✅ EmbeddingService API is similar, just async
- ✅ Both apps already do L2 normalization
- ✅ Tokenization logic unchanged

### Medium Risk:
- ⚠️ VectorStore API change (generic type, weight function)
- ⚠️ CorpusKitStudio needs @Observable wrapper
- ⚠️ BigBookViaLLM needs adapter for `[Chunk]` return type

### Testing Required:
- Verify embeddings are identical (before/after)
- Verify search results match (same queries, same rankings)
- Test with production corpus data
- Performance benchmarks (should be same or better)
