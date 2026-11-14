# CorpusKit Update Phases

## Context
CorpusKit is a shared Swift package (Swift 6) used by BigBookViaLLM (iOS) and CorpusKit Studio (macOS).
It provides `EmbeddingService`, `VectorStore`, and `UnifiedChunker`.
All work must keep eval and production code on identical paths.

---

## Phase 1 — Stabilize ✅ CLOSED

### 1a. Fix export bug
- Studio's chunker was writing incorrect page values for all chunks
- The `page` field was omitted from `chunks.json`
- Fix: verify `page` is included and correct in the `UnifiedChunker` encode path

### 1b. Delete legacy chunkers
- `TextChunker.swift` — replaced by `UnifiedChunker` (AD-7)
- `EPUBChunker.swift` — replaced by `UnifiedChunker` (AD-7)
- Confirm zero call sites, then delete; clean build and test suite required

### 1c. Architectural decision resolutions
- **corpusAuthority (AD-2b):** Reserved for future multi-corpus retrieval. Hardcoded to 1.0, never read.
  Add two comments only — in `UnifiedChunker` where set, and in `VectorStore.search()` where absent. No logic change.
- **Eval query alignment (AD-2c):** `EvalRunner.swift:178` — embed `test.question` not `test.expectedPassage`.
  Plus matching `SentenceRanker` call. One-line change; pass/fail numbers will shift — expected.

---

## Phase 2 — Domain Translation Corpus ~~✅ CLOSED~~ 🚫 SHELVED

> Arctic-embed-m-v1.5 scored 15/15 on original 1939 text with zero domain translation.
> The vocabulary bridging problem Arctic was chosen to solve does not require a parallel corpus.
> HomesteadAI translation pipeline, modernText field, and dual encoding are all shelved indefinitely.

**Goal:** Improve retrieval by bridging 1939 language to modern user vocabulary.

### Architecture
```
Studio (build time)
  UnifiedChunker → paragraph chunks (original text)
       ↓
  HomesteadAI → modern English translation per chunk
       ↓
  EmbeddingService → embed modern text
       ↓
  Store: { originalText, modernText, embedding }
       ↓
  Export .corpus.zip

BigBookViaLLM (runtime, on-device)
  User question → embed → search modern embeddings
       ↓
  Retrieve original text chunks → LLM summary + 3 references
```

### Changes required

**UnifiedChunker**
- Replace word-count windowing with paragraph-boundary splitting
- Paragraph = double newline or equivalent structural marker in source PDF
- Both PDF and EPUB paths need the new split strategy

**Chunk model**
- Add `modernText: String?` field
- `text` remains the original; `modernText` holds the HomesteadAI translation
- Embedding is always of `modernText` when present, `text` otherwise

**Studio pipeline — new translation step**
- After chunking, before embedding: pass each chunk's `text` to HomesteadAI
- Prompt: "Convert the following passage to clear modern English, preserving meaning exactly. Return only the converted text."
- Store result as `chunk.modernText`
- Translation runs once at corpus build time; results are cached in the exported bundle

**VectorStore**
- No search logic change — embeddings are already the search target
- Confirm embedding is sourced from `modernText` not `text` during index build

**BigBookViaLLM**
- No changes required
- Retrieval is transparent to the app

### Notes
- HomesteadAI is a build-time tool in Studio only — user questions never leave the device
- Privacy promise in BigBookViaLLM is fully preserved
- Run eval after re-export to confirm pass/fail improves vs Phase 1 baseline

---

## Phase 3 — Validation ✅ CLOSED

**Goal:** Confirm the package is correct end-to-end before new apps consume it.

- Run eval harness against the BigBookViaLLM corpus
- Confirm `page` values are correct in all exported `chunks.json` entries
- Confirm retrieval quality: top-3 results should match expected passages for all eval cases
- Confirm the 3-reference LLM response format is populated correctly from retrieved chunks
- All eval cases must pass before proceeding to Phase 4

---

## Phase 4a — Embedding Consolidation ✅ COMPLETE (Phase A + B)

> Done 2026-06-21. snowflake-arctic-embed-m-v1.5 (768-dim, seq 256) bundled in the CorpusKit
> target via Git LFS; loaded from `Bundle.module`; `EmbeddingModelInfo` is the single source of
> dimension/id/seqLength; corpus-load compat guard rejects mismatched corpora. Model converted as
> **mlprogram** (coremltools 9.0) — the legacy `neuralnetwork` backend collapsed the BERT encoder
> (all inputs → ~one vector); pooling + L2 are done client-side in Swift. Package tests pass with
> discriminating embeddings (cross-sim ~0.23–0.34). **All corpora must be re-embedded (384→768).**


### Model artifact ✅ COMPLETE
- `arctic-embed-m-v1.5.mlmodelc` compiled (416 MB) via PyTorch tracing + xcrun
- Toolchain: Python 3.11, torch 2.3.1, torchvision 0.18.1, transformers 4.47.1, coremltools 6.3.0
- Format: `neuralnetwork` (not mlprogram — libmilstoragepython unavailable in coremltools 6.3 binary)
- Saved as `.mlmodel` then compiled with xcrun (not `.mlpackage` — libmodelpackage same issue)
- Metadata written: `model_id`, `dimension=768`, `seq_length=256`, `pooling`, `normalised`
- PyTorch wrapper shape verified: (768,) ✓ for all eval sentences
- Inference parity (PyTorch vs Core ML): requires XCTest on-device — libcoremlpython unavailable in Python build
- Scripts: `05_pytorch_to_coreml.py`, `06_verify_pytorch_coreml.py`, `requirements_conversion.txt`

**Goal:** Single source of truth for model + inference before the reader is built.

### Why now
The Phase 4 reader cannot ship its own model copy — consolidation must happen first.
Phase A + B only; Phase C (corpus loader into package) defers until reader is active.

### Phase A — Bundle model in the package (~½ day) — **Option A (single target)**
Decision: keep the model + `EmbeddingService` in the existing `CorpusKit` target. A separate
`CorpusKitEmbedding` target would move `EmbeddingService` + `EvalRunner` + `SentenceRanker` out of
the `CorpusKit` module, breaking BigBookViaLLM's `import CorpusKit` (it uses `EmbeddingService` and
`EvalRunner` directly) — and BigBook must not be touched. Every real consumer embeds, so the
"no binary on type-only consumers" benefit is currently theoretical. Revisit the split if a
genuinely type-only consumer appears (and update BigBook in the same PR).
- **Model: snowflake-arctic-embed-m-v1.5** (replaces all-MiniLM-L6-v2)
  Eval: MiniLM 0/15, Arctic 15/15 on original 1939 Big Book text — no domain translation required.
  Dimension changes 384 → 768; all corpora must be re-embedded after consolidation.
- Convert model via existing `05_pytorch_to_coreml.py` pipeline before bundling
- Bundle `Resources/arctic-embed-m-v1.5.mlmodelc` + `vocab.txt` on the `CorpusKit` target.
- `Package.swift`: `.copy("Resources/arctic-embed-m-v1.5.mlmodelc")` + `.copy("Resources/vocab.txt")` — must be `.copy` not `.process`.
- `EmbeddingService.load()`: resolve via `Bundle.module` first, fall back to `Bundle.main`.
- Ship precompiled `.mlmodelc` not `.mlpackage` — avoids visible cold-start delay on iOS.
- Set up Git LFS for the model binary before first commit.

### Phase B — Model identity & compatibility (~½ day)
- Add `EmbeddingModelInfo { id: String; dimension: Int; revision: Int }` to package
- All hardcoded `384` literals replaced — Arctic dimension is 768; `EmbeddingModelInfo.dimension` is the single source
- Compatibility guard at corpus load: compare `corpus_meta` model id + dimension against loaded model; refuse/flag mismatch
- This is the safety net for every consumer when models are swapped

### Migration
- **CorpusKit Studio:** delete `Resources/MiniLMEmbedding.*` + `vocab.txt`; model now resolves from the package via `Bundle.module`; keep `@Observable` wrapper
- **BigBookViaLLM:** untouched — keeps its own copy as the `Bundle.main` fallback; can delete it later when explicitly instructed
- **Phase 4 reader:** model comes free from the `CorpusKit` package

### Bonus
- `Bundle.module` resolution finally enables real embedding unit tests in the package
- Deliver as one PR: Phase A + B together

---

## Phase 4 — CorpusKit Reader (iOS + Mac)

**Goal:** Universal corpus reader app built on the validated CorpusKit package.

### Platform
- Universal iOS + Mac app from day one — corpus format is already platform-agnostic
- iOS: on-device only, same privacy guarantee as BigBookViaLLM
- Mac: on-device default, plus opt-in HomesteadAI routing for users who want a stronger model

### Model tiering
| Device | Model | Capability |
|---|---|---|
| iPhone 15 Pro+ / compatible iPad | Apple Foundation Models (compact) | Good |
| M1+ iPad / Mac | Apple Foundation Models (full) | Better |
| Mac via HomesteadAI (opt-in) | Larger local or cloud model | Best |

### Corpus archive
- Ships with a curated archive of pre-built `.corpus.zip` bundles (Arctic-embedded)
- Rob and others can publish corpora to the archive
- Users can also sideload their own corpora built with CorpusKit Studio

### Notes
- HomesteadAI is opt-in on Mac only — not exposed on iOS
- On-device remains the default on all platforms
- General audience, not recovery-specific — HomesteadAI tradeoff is appropriate here

---

## Parked — PDF import quality (Studio `PDFImporter`)

Discovered 2026-06-21 comparing a PDF vs EPUB corpus of the same book. The EPUB corpus is clean
(structured chapters, no headers); the PDF corpus is polluted, which makes its retrieval diverge
badly from the EPUB's. Root causes, all in Studio's `PDFImporter`:

1. **Page-number extraction misfires** — `extractPrintedPageNumber` matched body text (a chunk got
   `bookPage = 1939`, the *year* from "reprint of the 1st edition 1939"). Must constrain to the
   header/footer region (short top/bottom line that is mostly a number).
2. **Running headers/footers not stripped** — "NN Alcoholics Anonymous" repeats into chunk text
   (degrading embeddings) and gets captured as chapter boundaries (39 bogus "chapters" like
   "170 Alcoholics Anonymous", "More About Alcoholism 51", "Chapter Page").
3. **Chapter map** — auto-detection latched onto headers/TOC; needs curated boundaries. This is also
   where **roman-numeral front-matter pages** should be marked (`bookStartPage` supports roman).

Until fixed, prefer the EPUB source for books that exist in both formats. The page-label +
EPUB-estimation work (committed) is unaffected.

## Rules for all phases
- Do not add features until the current phase's eval gate passes
- Only show changed files in output
- Do not modify `RAGEngine.swift` or any BigBookViaLLM files unless explicitly instructed
- Prefer test-driven iteration: write or update eval cases before implementing fixes
