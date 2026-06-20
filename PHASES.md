# CorpusKit Update Phases

## Context
CorpusKit is a shared Swift package (Swift 6) used by BigBookViaLLM (iOS) and CorpusKit Studio (macOS).
It provides `EmbeddingService`, `VectorStore`, and `UnifiedChunker`.
All work must keep eval and production code on identical paths.

---

## Phase 1 — Stabilize  ✅ COMPLETE (2026-06-20)

**Goal:** Fix known bugs and remove dead code before any new work.

### 1a. Fix export bug  ✅ resolved
Verified: `page` is in `Chunk.CodingKeys` (not omitted) and PDF `ContentUnit`s are per-page (`PDFImporterAdapter`), so `UnifiedChunker.chunkFlat` assigns the correct per-page value. No reproduction in current code.
- Studio's chunker is writing incorrect page values for all chunks
- The `page` field is being omitted from `chunks.json`
- Suspected cause: custom `CodingKeys` enum omitting the field, or incorrect page tracking in the word-level chunking loop
- Find the encode path in `UnifiedChunker` or its export step and verify `page` is included and correct

### 1b. Delete legacy chunkers
- `TextChunker.swift` — marked for deletion, replaced by `UnifiedChunker` (AD-7)
- `EPUBChunker.swift` — marked for deletion, replaced by `UnifiedChunker` (AD-7)
- Before deleting: confirm zero call sites and no test references to either file
- After deleting: run full build and test suite to confirm clean

---

## Phase 2 — Architectural Decision Resolutions  ✅ COMPLETE (2026-06-20)

**Goal:** Resolve open questions from the AD-1 through AD-21 walkthrough.
**Details:** see `ARCHITECTURE.md` → "Architectural decisions resolved (Phase 2)" (P2a–P2c).

### 2a. ProjectMetadata redundancy (AD-20)  ✅ removed
- Audited: zero references in CorpusKit, CorpusKitStudio, or BigBookViaLLM.
- `public struct ProjectMetadata` removed from `EvalTypes.swift`.

### 2b. corpusAuthority not used in retrieval scoring  ✅ documented (reserved)
- Decision: do NOT wire, do NOT remove. Reserved for future multi-corpus retrieval (CorpusKit for Mac).
- Single-corpus consumers correctly rank by `chapterWeight`.
- Intent comments added at the two `UnifiedChunker` set-sites and at `VectorStore.search()`.

### 2c. Eval harness query strategy  ✅ fixed
- `EvalRunner` now embeds `test.question` (not `expectedPassage`) for both vector search and `SentenceRanker`.
- Threshold recalibration deferred to Phase 3 validation.

---

## Phase 3 — Validation

**Goal:** Confirm the package is correct end-to-end before new apps consume it.

- Run eval harness against the BigBookViaLLM corpus
- Confirm `page` values are correct in all exported `chunks.json` entries
- Confirm retrieval quality: top-3 results should match expected passages for all eval cases
- Confirm the new 3-reference LLM response format in BigBookViaLLM is populated correctly from retrieved chunks
- All eval cases must pass before proceeding to Phase 4

---

## Phase 4 — CorpusKit for Mac

**Goal:** New Mac app — a RAG corpus reader built on the validated CorpusKit package.

- Uses the stable `CorpusKit` Swift package directly (no new package changes expected)
- Ships with a curated archive of pre-built `.corpus.zip` bundles
- Rob and others can publish corpora to the archive
- Design follows same privacy principle as BigBookViaLLM: fully on-device, no server

---

## Rules for all phases
- Do not add features until the current phase's eval gate passes
- Only show changed files in output
- Do not modify `RAGEngine.swift` or any BigBookViaLLM files unless explicitly instructed
- Prefer test-driven iteration: write or update eval cases before implementing fixes
