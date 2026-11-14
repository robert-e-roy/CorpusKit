# CorpusKit

The portable, on-device retrieval engine behind the CorpusKit family. A Swift package that
embeds text with a bundled Core ML model and searches pre-embedded corpora — no network, no
server, no analytics.

Consumers (all private apps — the repos aren't public):
- **CorpusKitStudio** (macOS) — authors, chunks, embeds, evaluates and exports corpora
- **CorpusKitReader** — loads and searches exported corpora
- **BigBookViaLLM** (iOS) — on-device RAG over a shipped corpus

Authoring (importers, chunkers, editing UI, export) lives in CorpusKitStudio (private). This package holds
only what both sides need, so a consumer queries a corpus through exactly the same embedding and
scoring path that was used to build and evaluate it. Design decisions are recorded in
[`ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## What's in the package

| Area | Types |
|------|-------|
| Embedding | `EmbeddingService`, `WordPieceTokenizer`, `EmbeddingModelInfo` |
| Vector search | `VectorStore<T>`, `VectorIndex`, `ScoredChunk` |
| Sentence reranking | `SentenceRanker`, `RankedSentence`, `RankableChunk` |
| Corpus consumption | `CorpusCatalog`, `CorpusDescriptor`, `CorpusBundleLoader`, `LoadedCorpus`, `CorpusSearch` |
| Data model | `Chunk`, `CorpusMetadata` |
| Evaluation | `EvalRunner`, `EvalTest`, `EvalResult`, `EvalSummary` |
| Archives | `ZipArchive` (cross-platform zip/unzip via ZIPFoundation) |

## Embedding model

The model ships **inside the package** as a precompiled resource, so every consumer uses the same
one — apps no longer bundle their own copy.

- **Model:** `Snowflake/snowflake-arctic-embed-m-v1.5`, Core ML `mlprogram`, precompiled to
  `Resources/arctic-embed-m-v1.5.mlmodelc` (~416 MB)
- **Output:** the model emits per-token embeddings; `EmbeddingService` mean-pools them in Swift
  (padding excluded via the attention mask) and L2-normalizes, giving 768-dimensional unit
  vectors, so cosine similarity is a plain dot product. Pooling is client-side because
  coremltools mis-converts the in-graph masked-mean ops.
- **Sequence length:** 256 tokens, read from the model's metadata at load time
- **Compute units:** forced to `.cpuOnly` (FP32). Query and corpus embeddings must come from the
  same compute path; letting each device pick the Neural Engine or GPU shifts the vectors and
  breaks ranking across platforms.

`EmbeddingModelInfo.current` is the single source of truth for the model id, dimension, sequence
length and revision. Exporters stamp it into `corpus_meta.json`, and `CorpusSearch` refuses a
corpus whose embedding dimension doesn't match the current model. To swap models, replace the
`.mlmodelc` and update `EmbeddingModelInfo.current` together. The conversion script that produced
the current model lives in the private CorpusKitStudio repo. The public
[PyTorch_to_CoreML](https://github.com/robert-e-roy/PyTorch_to_CoreML) repo shows the same
PyTorch-tracing approach, applied to the earlier all-MiniLM-L6-v2 model.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+ (swift-tools 5.9, Swift 5 language mode). Builds with the Swift 6 toolchain; the
  package has not yet adopted Swift 6 language mode.
- **Git LFS** — the model is stored in LFS. Run `git lfs install` before cloning, or
  `git lfs pull` afterwards; without it the `.mlmodelc` is a pointer file and model loading fails.
- One dependency: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (≥ 0.9.20), for
  cross-platform `.corpus` bundle extraction

## Installation

In Xcode, **File → Add Package Dependencies…**, enter
`https://github.com/robert-e-roy/CorpusKit`, and add the **CorpusKit** library to your app target.
Or in `Package.swift`:

```swift
.package(url: "https://github.com/robert-e-roy/CorpusKit", branch: "main")
```

(The author's own apps reference it as a local sibling checkout at `../CorpusKit`.)

No model or vocabulary resources need to be added to the app; they resolve from the package's
`Bundle.module`. (`EmbeddingService` still falls back to `Bundle.main` for apps that ship
their own copy.)

## Usage

### Search an exported corpus (the common case)

```swift
import CorpusKit

// 1. List available corpora — reads metadata only, no embeddings loaded
let catalog = CorpusCatalog()
let corpora = catalog.descriptors(sources: [
    (directory: Bundle.main.resourceURL!, source: .bundled),
    (directory: documentsURL, source: .local),
])

// 2. Load one (a `.corpus` bundle file, legacy `.corpus.zip`, or extracted `.corpus` directory)
let loader = CorpusBundleLoader()
try loader.ensureDownloaded(descriptor.url)          // no-op unless it's an iCloud item
let corpus = try loader.load(corpusZip: descriptor.url)
// or: try loader.load(corpusDirectory: extractedDir)

// 3. Search — throws `.incompatibleModel` if the corpus was embedded at another dimension
let search = try CorpusSearch(corpus: corpus)
try await search.loadModel()                         // optional; search() loads lazily
let results = try await search.search("What is the meaning of life?", k: 3, rankSentences: true)

for r in results {
    print(r.chunk.chapter, r.chunk.page, r.finalScore)   // finalScore = cosine × importance
    if let sentence = r.winningSentence { print("→", sentence) }
}
```

`descriptor.isCompatible` lets a picker grey out corpora built with a different model before
the user tries to open one.

### Embedding directly

```swift
let embedder = EmbeddingService()
try await embedder.load()

let vector = try await embedder.embed("A question")      // [Float], 768-dim, L2-normalized

// Batch, with progress (delivered on the main actor) and cooperative cancellation:
// cancelling the surrounding Task throws CancellationError between items.
let vectors = try await embedder.embedBatch(texts) { progress in
    print("\(Int(progress * 100))%")
}
```

### Generic vector search

`VectorStore<T>` works over any item type with your own weighting:

```swift
let store = VectorStore<MyItem>()
store.build(items: items, embeddings: embeddings)

let hits = store.search(query: queryVector, k: 5) { item in item.boost }
for hit in hits {
    print(hit.item, hit.rawScore, hit.weightedScore)
}
```

`VectorIndex` is the `Chunk`-specific wrapper that weights by `chunk.importance`, and is what
`CorpusSearch` uses.

## Corpus bundle format

An exported corpus is a zip of a `<Title>_v<N>.corpus/` directory containing at least:

- `corpus_meta.json` — `CorpusMetadata`, including the embedding model id and dimension
- `chunks.json` — `[Chunk]` (text and location; embeddings excluded)
- `embeddings.npy` — float32 matrix, one row per chunk, in chunk order

Bundles are written with the single extension **`.corpus`** (AD-22). The older double extension
`.corpus.zip` is still read but no longer written. `CorpusCatalog.isCorpusBundleName(_:)` and
`bundleBaseName(_:)` handle both.

## Logging

Engine diagnostics (emoji-prefixed traces) go through an internal `dlog` and are **off by
default**, so they don't flood the host app's console. To turn them on in a DEBUG build of a host
app:

```bash
defaults write <host.bundle.id> CKVerboseLogging -bool YES
```

…or set `CKDebugLog.forceEnabled = true` in `DebugLog.swift`.

## Testing

```bash
swift test
```

Tests use Swift Testing (`import Testing`).

## Further reading

- [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture decisions log (shared with the private CorpusKitStudio app)
- [`PHASES.md`](docs/PHASES.md), [`PHASE4A_CLAUDE_CODE.md`](docs/PHASE4A_CLAUDE_CODE.md) — consolidation phases and history
- The `docs/INTEGRATION.md`, `docs/MIGRATION_CHECKLIST.md`, `docs/QUICK_REFERENCE.md`, `docs/DIFFERENCES.md`,
  `docs/SUMMARY.md` and `docs/INDEX.md` files date from the original MiniLM-era extraction and are
  historical; where they conflict with this README or `ARCHITECTURE.md`, they are out of date.

## License

MIT — see [`LICENSE`](LICENSE).

Third-party components keep their own licenses:
- The bundled embedding model is a Core ML conversion of
  [Snowflake/snowflake-arctic-embed-m-v1.5](https://huggingface.co/Snowflake/snowflake-arctic-embed-m-v1.5)
  (Apache-2.0), including its `vocab.txt`.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) is MIT.
