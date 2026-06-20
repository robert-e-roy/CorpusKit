# Architecture Decisions Log — CorpusKit & CorpusKit Studio

**Snapshot date:** 2026-06-19

This document records the architectural decisions **as implemented in the code today**, across two repositories:

- **CorpusKit** — the portable engine (this package): `/Users/robroy/Projects/CorpusKit`
- **CorpusKit Studio** — the macOS authoring app: `/Users/robroy/Projects/CorpusKitStudio`

It is a *snapshot*, not a roadmap. Only decisions reflected in actual code are recorded. Where the code shows a decision was made but its rationale or current correctness is unclear, the entry is marked **Status: Undocumented — needs review**.

Dates are inferred from git history (commit dates) where a decision maps to an identifiable commit; otherwise the snapshot date is used.

---

## Index

| AD | Title | Status |
|----|-------|--------|
| AD-1 | Two-module split: portable engine vs. macOS app | Accepted |
| AD-2 | On-disk project format: flat-file working directory | Accepted |
| AD-3 | Export bundle format: `.corpus.zip` via `ditto` + SHA256 signature | Accepted |
| AD-4 | Unified `DocumentImporter` protocol; separate PDF and EPUB paths | Accepted |
| AD-5 | Import defers chunking (`skipChunking`) until chapter editing is done | Accepted |
| AD-6 | EPUB chapter indexing keyed on `globalChapterIndex`, not TOC navPoints | Accepted |
| AD-7 | `UnifiedChunker`: flat sliding window (PDF) vs. per-unit window (EPUB) | Accepted |
| AD-8 | Re-chunking preserves embeddings where chunk text is unchanged | Accepted |
| AD-9 | Embedding model: MiniLM-L6-v2 Core ML, 384-dim, L2-normalized | Accepted |
| AD-10 | Mean pooling with attention mask (padding excluded) | Accepted |
| AD-11 | In-app WordPiece tokenizer, max length 128 | Accepted |
| AD-12 | `VectorStore` similarity: vDSP dot product over L2-normalized vectors | Accepted |
| AD-13 | Retrieval weighting by per-chunk `importance`; hardcoded chapter weights removed | Accepted |
| AD-14 | Sentence-level reranking via `SentenceRanker` | Accepted |
| AD-15 | Authority rank → weight fixed mapping | Accepted |
| AD-16 | Chunk importance = chapter base × highlight boosts | Accepted |
| AD-17 | `EvalRunner` queries with the *expected passage* embedding, not the question | Accepted |
| AD-18 | Chapter editor data model and `chapter_config.json` | Accepted |
| AD-19 | `eval_result.json` and `eval_report.pdf` generated at export time | Accepted |
| AD-20 | Single canonical export path and one `CorpusMetadata` schema | Accepted |
| AD-21 | One canonical `.corpuskit` storage location + bookmark rediscovery | Accepted |

---

## Module boundary & packaging

### AD-1: Two-module split — portable engine vs. macOS app

**Status:** Accepted
**Date:** 2026-05-02 (`extract corupskit`) → 2026-05-04 (engine package created)

**Context:**
Retrieval/embedding logic needs to be reusable by downstream consumer apps that ship a finished corpus, not just by the authoring tool. Keeping that logic inside the macOS app would couple portable model/retrieval code to AppKit, sandboxing, and the editing UI.

**Decision:**
The codebase is split into a pure Swift package (`CorpusKit`) and a macOS app (`CorpusKitStudio`) that depends on it via a local `XCLocalSwiftPackageReference` (`relativePath = ../CorpusKit`). The engine is `swift-tools-version: 5.9`, targets iOS 17 / macOS 14, and declares **zero dependencies** (`Package.swift`). It exports the portable primitives: `Chunk`, `EmbeddingService`, `WordPieceTokenizer`, `VectorStore`, `VectorIndex`, `SentenceRanker`, `EvalRunner`, and the shared eval/metadata types (`EvalTypes.swift`: `ProjectMetadata`, `EvalTest`, `EvalResult`, `EvalSummary`).

The app keeps everything platform- or authoring-specific: importers, chunkers, the file-based workspace, the editing UI, and the export pipeline. Engine types are imported with `import CorpusKit`; the app does **not** redefine them.

**Consequences:**
- Enables a consumer app to embed a query and run the exact same `VectorStore`/`SentenceRanker` search path used during authoring.
- Constrains the engine to Foundation + Accelerate + CoreML only (no AppKit), so all UI/state lives in the app.
- Editing engine logic means editing files outside the app repo.
- Some seams cross the boundary awkwardly: `EvalTypes.swift` (engine) defines `ProjectMetadata` with `format_version`, while the app defines its own `CorpusMetadata` (`WorkingDirectory.swift`) with `bundle_schema_version`. Two metadata notions coexist (see AD-20).

---

### AD-2: On-disk project format — flat-file working directory

**Status:** Accepted
**Date:** 2026-04-17

**Context:**
The app needs durable, inspectable, diff-friendly project storage without a database, and must work inside the macOS sandbox container.

**Decision:**
Each project is a plain directory of individual files, defined by `WorkingDirectory` (`Model/WorkingDirectory.swift`). There is **no database**. Per-project files include:

- `source.pdf` — source document (or link to it)
- `corpus_meta.json` — `CorpusMetadata` (Codable; carries `bundle_schema_version`, chunking config, authority config, processing flags)
- `chunks.json` — `[Chunk]`
- `embeddings.npy` — embeddings as NumPy `.npy` (float32, C-order)
- `importance.json`, `query_expansion.json`, `highlights.json`, `text_highlights.json`
- `chapters.json`, `eval_tests.json`, `eval_results.json`, `original_chapters.json` (EPUB)
- `corpus.sig` — SHA256 signature, regenerated on export

`CorpusMetadata` has a hand-written `init(from:)` decoder that tolerates a missing `wordsPerPage` (defaults to 280) for backward compatibility, establishing the precedent that persisted-shape changes are migrations.

**Consequences:**
- Projects are transparent and recoverable by hand; no schema engine required.
- Each mutation writes a JSON file (see `CorpusWorkspace` property `didSet` writers), trading write amplification for simplicity.
- Any change to a persisted shape must respect/bump a schema version and not break existing on-disk projects.

---

### AD-3: Export bundle format — `.corpus.zip` via `ditto` + SHA256 signature

**Status:** Accepted
**Date:** 2026-04-17 (`CorpusExporter` created)

**Context:**
A finished corpus must ship as a single portable artifact that a consumer app can verify and unpack, produced from on-device files inside a sandbox.

**Decision:**
`CorpusExporter.export()` (`Pipeline/CorpusExporter.swift`) assembles a `<SafeTitle>_v<N>.corpus/` directory in a temp location, writes the corpus files into it, and zips it with `/usr/bin/ditto -c -k --sequesterRsrc --keepParent`, producing `<SafeTitle>_v<N>.corpus.zip`. The bundle carries a `corpus.sig` = `SHA256(chunks.json bytes + embeddings.npy bytes)`, hex-encoded. Embeddings are serialized to `.npy` by a hand-rolled encoder (`encodeNpy`, 64-byte aligned header, `<f4`, `fortran_order: False`).

On the import side, `WorkspaceManager.importBundle()` extracts with `ditto -x -k`, locates the inner directory by `pathExtension == "corpus"`, and refuses bundles whose `bundleSchemaVersion > 1`.

**Consequences:**
- Self-contained, OS-native (un)zipping; no third-party archive dependency.
- Signature lets a consumer detect tampering/corruption of the two heavy artifacts.
- The `.npy` writer is bespoke; any change to embedding dtype/shape must keep header generation in sync with NumPy expectations.
- See AD-20: the importer's `corpus_meta.json` expectations don't fully match what the active exporter writes.

---

## Import

### AD-4: Unified `DocumentImporter` protocol; separate PDF and EPUB paths

**Status:** Accepted
**Date:** 2026-05-07 (`add epub and new project support`)

**Context:**
Two source formats with very different structure (paged PDF vs. reflowable EPUB) must feed one chunking/embedding pipeline.

**Decision:**
A `DocumentImporter` protocol (`Pipeline/DocumentImporter.swift`) defines `importDocument(url:config:) -> DocumentImportResult` and `validateDocument(url:)`. Both formats normalize into `ContentUnit` (index, text, title, `DocumentLocation`) so downstream chunking is format-agnostic. The two implementations and their adapters (`PDFImporter`/`PDFImporterAdapter`, `EPUBImporter`/`EPUBImporterAdapter`) keep format-specific extraction isolated:

- **PDF** (`PDFImporter`): one `ContentUnit` per page; attempts to extract the *printed* page number from page text (`extractPrintedPageNumber`), recording a `PageNumberSource` (`extracted` / `inherited` / `fallback` / `estimated`). Produces `pages` with `bookPage` where detectable.
- **EPUB** (`EPUBImporter`): parses the OPF spine for reading order, extracts one `ContentUnit` per chapter, splitting multi-chapter files by TOC anchors. Pages don't exist, so chunks carry `paragraph` + `sourceFile`; book pages are estimated from `wordsPerPage` (default 280).

**Consequences:**
- The chunker (AD-7) consumes `ContentUnit` and never branches on file type beyond a `chunkPerUnit` flag.
- PDF page provenance is explicitly tracked and surfaced in the UI (`Chunk.displayLocation` prefixes estimated pages with `~`).
- Two large, format-specific extractors (`EPUBImporter` is ~850 lines) must be maintained independently.

---

### AD-5: Import defers chunking (`skipChunking`) until chapter editing is done

**Status:** Accepted
**Date:** 2026-05-07

**Context:**
Chunk chapter assignment and importance depend on the chapter map, which the user edits after seeing detected chapters. Chunking/embedding before that edit would waste the expensive embedding step and produce wrong chapter labels.

**Decision:**
`WorkspaceStore.importDocument(..., skipChunking: true)` (`Pipeline/WorkspaceStore.swift`) defaults to creating the project with chapter rows detected but **no chunks/embeddings**. Processing status becomes `"Ready - Edit chapters, then chunk & embed"`. Chunking + embedding (`chunkAndEmbed` / `chunkEPUB`) runs only when explicitly triggered, or on `rechunkWorkspace`.

**Consequences:**
- Chunks and embeddings cannot be assumed to exist immediately after import.
- The user can correct the chapter map before paying the embedding cost.
- Workflow is two-phase (import → edit → chunk/embed), reflected throughout the UI.

---

### AD-6: EPUB chapter indexing keyed on `globalChapterIndex`, not TOC navPoints

**Status:** Accepted
**Date:** 2026-05-07

**Context:**
EPUB spine files without TOC entries make the TOC `navPoint` position diverge from the actual reading-order chapter position. Indexing chapters by TOC position would misalign chapter rows with content.

**Decision:**
In `EPUBImporter`, chapters are assigned a running `globalChapterIndex` as the spine is walked (incremented per emitted chapter, including anchor-split segments). `WorkspaceStore.importDocument` builds chapter rows from this index so that `startPage == unit.location.page` holds exactly (EPUB "page" = `chapterIndex + 1`). The chunker matches a chunk to a chapter boundary primarily by `boundary.startPage == unit.location.page`, with a title-based fallback for workspaces created before this fix (`UnifiedChunker.chapterImportanceForUnit`).

**Consequences:**
- Chapter rows line up with extracted content even when the TOC is sparse or absent.
- The page/index invariant (`startPage == unit.location.page`) must be preserved by anything that builds EPUB chapter rows.
- A title-match fallback is retained for older projects, accepting some ambiguity when titles repeat.

---

## Chunking

### AD-7: `UnifiedChunker` — flat sliding window (PDF) vs. per-unit window (EPUB)

**Status:** Accepted
**Date:** 2026-05-14 (`add pages and chunking`) → 2026-05-17 (`chunker bug fix`) → 2026-06-19 (legacy chunkers deleted)

**Context:**
A single chunking implementation should serve both formats while respecting that PDF text flows continuously across pages whereas EPUB chapters are hard boundaries that should never bleed together.

**Decision:**
`UnifiedChunker` (`Pipeline/UnifiedChunker.swift`) is word-based with a configurable window (`chunkSize` words, `chunkOverlap` words, `minChunkSize`) and a `chunkPerUnit` flag:

- **PDF (`chunkFlat`):** all words across all pages are concatenated into one stream; a sliding window steps by `chunkSize - chunkOverlap`. Each chunk inherits the location of its first word.
- **EPUB (`chunkPerUnit`):** the window resets at every chapter and never crosses unit boundaries. Units under 200 chars are skipped as structural dividers. Section headers inside a chapter force a break (`sectionBreaks`).

Shared behaviors: chunk boundaries are nudged to the next sentence start (`advanceToSentenceBoundary`, up to 20 words); fragment chunks are dropped (`fragmentReason`: too short, starts lowercase, or starts with a conjunction/relative pronoun); dropped chunks advance the cursor by 1 so no text is skipped between accepted chunks. Per-format defaults come from `ChunkingConfig.ChunkingPreset` (Fiction 150/30, Non-fiction 200/40, Technical 100/20).

`UnifiedChunker` is the **sole** chunker. It is invoked by `WorkspaceStore.rechunkWorkspace`, which performs both the first chunk+embed (after the user reviews the chapter map) and all subsequent re-chunks. Import always defers chunking (AD-5), so there is no eager chunk-on-import path.

**Consequences:**
- EPUB chunks stay within a single chapter; PDF chunks can span page boundaries (correct for continuous prose).
- Chunk text is words rejoined with single spaces — original newlines are lost, which `SentenceRanker` must compensate for (see AD-14, `stripLeadingHeading`).
- One chunker, one code path. The earlier per-format chunkers (`TextChunker` for PDF, `EPUBChunker` for EPUB) and the dead `WorkspaceStore.chunkAndEmbed` / `chunkEPUB` eager-import methods that used them were **deleted on 2026-06-19**; the now-vestigial `skipChunking` parameter on `importDocument` was removed at the same time. Importers (`PDFImporter`/`EPUBImporter` and their `*Adapter`s producing `ContentUnit`s) are unaffected.

---

### AD-8: Re-chunking preserves embeddings where chunk text is unchanged

**Status:** Accepted
**Date:** 2026-05-14

**Context:**
Embedding is the most expensive pipeline step. Editing the chapter map or importance shouldn't force a full re-embed when chunk *text* hasn't changed.

**Decision:**
`WorkspaceStore.rechunkWorkspace` (`Pipeline/WorkspaceStore.swift`) compares new chunks against old, three ways:
1. **No change** (text + importance identical, same count): all old embeddings carried over, zero re-embedding.
2. **Same count, content/importance changed:** embeddings preserved per-index *where text matches*; only changed-text chunks are re-embedded.
3. **Count changed:** full re-embed.

**Consequences:**
- Importance/chapter edits are effectively free (no re-embedding).
- The optimization depends on positional (index-aligned) comparison; chunk reordering would defeat it.
- This behavior must be preserved in any future change to `rechunkWorkspace`.

---

## Embedding

### AD-9: Embedding model — MiniLM-L6-v2 Core ML, 384-dim, L2-normalized

**Status:** Accepted
**Date:** 2026-04-17 (`add ml`) → 2026-05-04 (moved into engine)

**Context:**
The product promise is fully on-device, network-free semantic search. That requires a small, fast sentence-embedding model runnable on the Neural Engine.

**Decision:**
`EmbeddingService` (`Sources/CorpusKit/EmbeddingService.swift`) loads `all-MiniLM-L6-v2` converted to Core ML (`MiniLMEmbedding.mlpackage`, with `.mlmodelc` fallback) from the app bundle, with `computeUnits = .cpuAndNeuralEngine`. Output dimension is fixed at **384**. Every embedding is **L2-normalized** before being returned (`l2Normalize` via `vDSP_svesq`), so downstream cosine similarity reduces to a dot product (AD-12). `embedBatch` embeds sequentially with a progress callback. The app wraps the service in an `@Observable EmbeddingServiceWrapper` that marshals progress to the main actor. A `#if DEBUG` diagnostic (`runEmbeddingDiagnostic`) asserts that unrelated phrases score < 0.3 and magnitudes ≈ 1.0, to catch silent model degradation.

**Consequences:**
- No network, no analytics; all inference is local.
- The 384-dim and `all-MiniLM-L6-v2` identity are written into export metadata (`dimension: 384`, `model: "all-MiniLM-L6-v2"`), so consumers must match.
- Sequential batch embedding bounds memory but is the pipeline's throughput limit.

---

### AD-10: Mean pooling with attention mask (padding excluded)

**Status:** Accepted
**Date:** 2026-05-04

**Context:**
MiniLM-L6-v2 sentence embeddings require **mean pooling** over token hidden states. The converted model also exposes a pre-pooled output (`var_548`) that may pool over *padding* tokens, which silently corrupts embeddings (all-similar vectors).

**Decision:**
`EmbeddingService.embed` prefers the per-token hidden states (`hidden_states`, fallback `last_hidden_state`) and pools them itself in `meanPool`, **summing only positions where the attention `mask == 1`** and dividing by the active-token count, then L2-normalizing. The pre-pooled `var_548` output is used only as a last resort and logs an explicit warning that it may include padding. A DEBUG inspection logs active vs. padding token counts on the first call.

**Consequences:**
- Embeddings reflect real tokens only; padding no longer drags vectors toward a common mean.
- The code is coupled to the specific output feature names produced by the conversion (`hidden_states` / `last_hidden_state` / `var_548`); regenerating the `.mlpackage` with different output names would require updating this method.

---

### AD-11: In-app WordPiece tokenizer, max length 128

**Status:** Accepted
**Date:** 2026-05-04

**Context:**
The Core ML model takes `input_ids` + `attention_mask`; tokenization must match BERT/MiniLM WordPiece vocabulary on-device with no dependency.

**Decision:**
`WordPieceTokenizer` (`Sources/CorpusKit/WordPieceTokenizer.swift`) implements greedy longest-match WordPiece against a vocab loaded from `vocab.json` (`{token: id}`) or `vocab.txt` (line-delimited). It lowercases, adds `[CLS]`/`[SEP]`, pads to **maxLength 128** with `[PAD]`, builds the attention mask (1 for real tokens, 0 for padding), and validates that `[CLS]`/`[SEP]`/`[UNK]`/`[PAD]` exist. Sequences longer than 128 are truncated (preserving a trailing `[SEP]`).

**Consequences:**
- No tokenizer dependency; deterministic and portable.
- Inputs longer than ~128 tokens are truncated, so very long chunks lose their tail — a constraint on `chunkSize` choices.
- Tokenization is whitespace-split then WordPiece; it does not implement full BERT basic-tokenization (punctuation splitting), which can differ subtly from reference implementations.

---

## Retrieval

### AD-12: `VectorStore` similarity — vDSP dot product over L2-normalized vectors

**Status:** Accepted
**Date:** 2026-05-04

**Context:**
On-device retrieval over a few thousand chunks needs to be fast without a vector-DB dependency, and cosine similarity is the natural metric for normalized sentence embeddings.

**Decision:**
`VectorStore<T>` (`Sources/CorpusKit/VectorStore.swift`) holds items + their pre-computed embeddings and scores a query with `vDSP_dotpr` per stored vector. Because all vectors are L2-normalized (AD-9), the dot product **is** cosine similarity — no division needed. `search(query:k:weightFunction:)` returns `ScoredChunk` carrying both `rawScore` (pure cosine) and `weightedScore` (cosine × optional weight), sorted by weighted score. It is a brute-force linear scan (no ANN index).

**Consequences:**
- Simple, dependency-free, and exact; fast enough for corpus-sized data.
- Linear scan won't scale to very large corpora without an index.
- Keeping `rawScore` separate from `weightedScore` lets callers (e.g. eval) judge on unweighted similarity while consumers rank on weighted (AD-13, AD-17).

---

### AD-13: Retrieval weighting by per-chunk `importance`; hardcoded chapter weights removed

**Status:** Accepted
**Date:** 2026-05-02 (`add testomg` — removal commit)

**Context:**
The original app-side `VectorIndex` hardcoded a Big-Book-specific chapter→weight table (e.g. `"How It Works": 1.2`, `"Our Southern Friend": 0.6`) and multiplied cosine by `corpusAuthority × chapterWeight × chunkImportance × usageSignal`. That made retrieval corpus-specific and unfit for a generic authoring tool.

**Decision:**
The hardcoded `chapterWeights` table and the composite weight formula were deleted. The engine `VectorIndex` (`Sources/CorpusKit/VectorIndex.swift`) now weights purely by the chunk's own `importance` field (a curator-set 0.0–1.0 value), computing `finalScore = rawCosine × importance`. All corpus-specific knowledge moved into the per-chunk `importance` value produced during authoring (AD-16), rather than living in retrieval code.

Note: `EvalRunner` (AD-17) calls `VectorStore.search` with **no** weight function, so evaluation judges on raw cosine; importance weighting is applied by `VectorIndex` for consumer-app retrieval.

**Consequences:**
- Retrieval is corpus-agnostic; any document benefits from authored importance without code changes.
- The `usageScore` server-feedback signal is no longer multiplied into the score in the current path (the field still exists on `Chunk`).
- Eval results and consumer retrieval rank differently by design (unweighted vs. importance-weighted).

---

### AD-14: Sentence-level reranking via `SentenceRanker`

**Status:** Accepted
**Date:** 2026-05 (engine)

**Context:**
A retrieved chunk (≈150–200 words) is too coarse to highlight the actual answer. The product needs to point at the single most relevant sentence and offer precise character offsets for highlighting.

**Decision:**
`SentenceRanker` (`Sources/CorpusKit/SentenceRanker.swift`) splits each retrieved chunk into sentences (tracking character offsets), filters to sentences ≥ 5 words, caps at 20 sentences per chunk to bound embedding cost, embeds them, and picks the highest cosine match against the query. It returns `RankedSentence` with text, score, `chunkID`, character offset/length, and one sentence of context before/after. Because chunk text is space-joined (newlines lost, AD-7), `stripLeadingHeading` strips an all-caps heading from the front of a chunk before splitting, so headings don't bleed into the first sentence. The sentence fields on `Chunk` (`winningSentence`, `sentenceScore`, `sentenceCharacterOffset`, `sentenceCharacterLength`) are explicitly **excluded from `Codable`** (omitted from `CodingKeys`) — they are ephemeral eval/UI state, never persisted to `chunks.json`.

**Consequences:**
- Enables precise highlight ranges in the reader UI and in eval output.
- Re-embeds sentences at query time (bounded to 20/chunk) — extra inference cost vs. chunk-only retrieval.
- Sentence splitting is heuristic (`.`/`?`/`!` + whitespace) and English-oriented.

---

## Authority & importance

### AD-15: Authority rank → weight fixed mapping

**Status:** Accepted
**Date:** 2026-04 → 2026-05

**Context:**
Curators express a document's authority on a 1–5 rank; the pipeline needs a concrete corpus-level weight from that rank.

**Decision:**
`WorkspaceStore.authorityWeightForRank` maps rank to weight with a fixed table: **1 → 1.5, 2 → 1.2, 3 → 1.0, 4 → 0.8, else → 0.6**. The resulting weight is stored in `CorpusMetadata.authorityWeight` and stamped onto every chunk's `corpusAuthority` at export (`CorpusExporter.prepareChunksForExport`). Chunks created during chunking default `corpusAuthority` to `1.0` until export stamps the real value.

**Consequences:**
- Authority is a simple, predictable multiplier carried in metadata and per chunk.
- The mapping is hardcoded (not user-tunable) and lives in the app, not the engine.
- `corpusAuthority` is not multiplied into the current retrieval score (AD-13); it is exported for downstream consumers to use as they see fit.

---

### AD-16: Chunk importance = chapter base × highlight boosts

**Status:** Accepted
**Date:** 2026-04-19 (`clear up importance`)

**Context:**
The single per-chunk `importance` value (which now drives retrieval weighting, AD-13) must combine the chapter's editorial weight with curator highlights marking especially important passages.

**Decision:**
`CorpusWorkspace.recalculateChunkImportance` (`Model/CorpusWorkspace.swift`) computes importance in two stages:
1. **Chapter base** (`applyChapterImportance`): each chunk's importance is set from its chapter row's importance level — `full → 1.0`, `reduced → 0.85`, `low → 0.6` (excluded chapters → 0.0). The same mapping is applied at chunk-creation time in `UnifiedChunker` (default 0.5 when no boundary matches).
2. **Highlight boosts** (`applyHighlightBoosts`): PDF highlights (`calculateHighlightBoost`, `0.08 × rating`, capped at 0.4) plus source-text highlights (`calculateTextHighlightBoost`, by character-range overlap, capped at 0.4) are added, with the final importance clamped to `min(…, 1.0)`.

This runs after chunk/embed and after loading a workspace, and writes `chunks.json` once.

**Consequences:**
- Importance is a derived value recomputed from chapter settings + highlights, not edited directly per chunk.
- Re-running is idempotent given the same inputs, which is what lets re-chunk preserve embeddings on importance-only changes (AD-8).
- Highlight boosts are capped so a heavily-highlighted low-importance chapter can't exceed full importance.

---

## Evaluation & export artifacts

### AD-17: `EvalRunner` queries with the *expected passage* embedding, not the question

**Status:** Accepted
**Date:** 2026-05

**Context:**
The corpus is built for semantic passage retrieval. Evaluating retrieval with a natural-language *question* embedding measures question→passage matching, which conflates query-understanding with the corpus's actual job (passage indexing). The author wants to know whether the expected passage is reliably retrievable.

**Decision:**
`EvalRunner.run` (`Sources/CorpusKit/EvalRunner.swift`) embeds `test.expectedPassage` (not `test.question`) and searches the `VectorStore` with `k = 5`. `test.question` is retained only as a human-readable label in the result. A test passes when the effective score ≥ `test.matchThreshold` (default 0.75). When `useSentenceRanking` is on, the effective score is the best sentence score (AD-14); otherwise it's the top chunk's raw cosine. Search uses no weight function, so eval judges on raw cosine (consistent with AD-13).

**Consequences:**
- Eval measures passage-indexing quality directly and is decoupled from query phrasing.
- A test's `question` text has no effect on pass/fail — only `expectedPassage` and `matchThreshold` do. This is intentional but surprising if read casually.
- Eval ranking (unweighted, k=5) differs from consumer retrieval (importance-weighted via `VectorIndex`).

---

### AD-18: Chapter editor data model and `chapter_config.json`

**Status:** Accepted
**Date:** 2026-05-05 (`chapter editor`)

**Context:**
Curators must rename, merge, exclude, re-weight, and manually insert chapter boundaries, and that editorial intent must survive into the exported bundle so transformations are reproducible.

**Decision:**
Two related models exist:
- **`ChapterBoundary`** (`Pipeline/PDFOutlineExtractor.swift`) — the working/editing type: `title`, `startPage`/`endPage`, `chapterType` (content/front_matter/appendix), `isExcluded`, `rawDetectedName`, `mergedInto`, `isManual`, `importance` (full/reduced/low), `bookStartPage` (Int or roman numeral string).
- **`ChapterConfig`** (`Model/CorpusPackage.swift`) — the serialized export form, with `chapters` (entries), `merges` (from→into), and `manualChapters`.

At export, `CorpusExporter.generateChapterConfig` projects boundaries into a `ChapterConfig` and writes **`chapter_config.json`** (described in code as "version 3+"). `applyChapterTransformations` applies edits to chunks in a fixed order: **manual chapters → merges → exclusions**. (As of AD-20, chapter data lives solely in `chapter_config.json`; the redundant `chapter_map` previously embedded in `corpus_meta.json` was removed when the metadata moved to the unified `CorpusMetadata` schema.)

**Consequences:**
- The bundle records both the *effect* (transformed chunks) and the *intent* (`chapter_config.json` with merges/manual/importance), enabling reproducible or re-applied transformations.
- Chapter identity flows by *title* through merges/exclusions (`applyChapterTransformations` matches on `chunk.chapter == merge.from`), so duplicate or renamed titles must be handled carefully.
- The editing type (`ChapterBoundary`) and serialized type (`ChapterConfig`) must be kept in sync by `generateChapterConfig`.

---

### AD-19: `eval_result.json` and `eval_report.pdf` generated at export time

**Status:** Accepted
**Date:** 2026-05

**Context:**
A shipped corpus should carry evidence of its retrieval quality, both machine-readable and human-readable.

**Decision:**
When an evaluation has been run and a `ChunkingConfig` is available, `CorpusExporter.writeCorpusFiles` invokes `EvalReportGenerator.generateReports` (`Pipeline/EvalReportGenerator.swift`), which writes **`eval_result.json`** (the `[EvalResult]` payload) and renders **`eval_report.pdf`** into the bundle directory, tagged with corpus id, timestamp, chunking preset, chunk size, and overlap. `eval_tests.json` (the test definitions) is also exported when present, so evaluations can be re-run downstream.

**Consequences:**
- Bundles are self-documenting about retrieval quality at export time.
- Reports are only generated when eval results + chunking config exist; otherwise they're silently omitted.
- Note the singular `eval_result.json` in the export bundle vs. the working directory's `eval_results.json` (plural) — two different filenames for related data.

---

## Foundations resolved (Phase 1)

The two issues below were flagged "Undocumented — needs review" in the original snapshot. Phase 1 resolved both; the entries now record the decision that was implemented and its rationale.

### AD-20: Single canonical export path and one `CorpusMetadata` schema

**Status:** Accepted
**Date:** 2026-06-19 (Phase 1)

**Context:**
Two export mechanisms had existed with incompatible bundle layouts and metadata schemas:
1. `CorpusExporter.export()` — the only path reachable from the UI — built a `<title>_v<N>.corpus/` directory and hand-wrote `corpus_meta.json` via `JSONSerialization` keyed `bundle_format_version: 2`, with a field set entirely different from `CorpusMetadata`.
2. `WorkspaceManager.exportBundle()` (reached only via the call-less `WorkspaceStore.exportWorkspace`) — zipped the working directory, whose `corpus_meta.json` is a Codable `CorpusMetadata` keyed `bundle_schema_version: 1`.

`WorkspaceManager.importBundle()` decodes the inner `corpus_meta.json` as `CorpusMetadata` (expecting `bundle_schema_version`), so it could **never** decode a `CorpusExporter`-produced bundle. Two exporters writing mutually-incompatible bundles is a foundation-level defect.

**Decision:**
- **`CorpusExporter.export()` is the single canonical export path.** It is the richer path (chapter transformations, `importance.json`, `chapter_config.json`, eval reports, `.npy` encoding, signature) and the only one the UI invokes.
- **`WorkspaceManager.exportBundle()` and its helpers (`regenerateSignature`, `sanitizeName`) and the unused `WorkspaceStore.exportWorkspace` were removed.** A comment at the old site documents the retirement and forbids reintroducing a second exporter.
- **One metadata struct, one key, one version.** `CorpusExporter` now writes `corpus_meta.json` by encoding a `CorpusMetadata` via `JSONEncoder` (ISO-8601 dates), derived from the project's working metadata with export fields overridden. The redundant `chapter_map` was dropped from the metadata (full chapter data already lives in `chapter_config.json`). Consumer-facing values that used to live only in the bundle meta (`source`, `copyright`, `license_type`, `curator`, `embedding_model`, `embedding_dimension`, `chunk_count`, `exported_at`) are preserved as **optional** fields on `CorpusMetadata`, omitted from working-directory files.
- **Migration:** `CorpusMetadata.init(from:)` reads the canonical `bundle_schema_version` and tolerates the legacy `bundle_format_version`. Because the legacy key lived in a different namespace (its value `2` meant "export-bundle format", not schema 2), a legacy-keyed file is **normalized to the current schema version (1)** rather than copying its number — which keeps it within `importBundle`'s `<= 1` guard. Only `bundle_schema_version` is ever written back.

**Consequences:**
- A bundle produced by `CorpusExporter.export()` now decodes cleanly as `CorpusMetadata`, so `importBundle()` round-trips. Covered by `exportedBundleMetadataDecodesAsCorpusMetadata` (full export → ditto-extract → decode) and `corpusMetadataRoundTripsViaCodable` / `corpusMetadataMigratesLegacyBundleFormatVersion`.
- The exported bundle's `corpus_meta.json` field set changed (now `CorpusMetadata`, not the old hand-built shape). This is a deliberate consumer-facing schema change; downstream readers must read the unified keys.
- **Pre-existing `CorpusExporter` bundles** (the old `bundle_format_version: 2` shape) remain non-importable — they lack `id`/`source_file_name`/dates/chunk config that `CorpusMetadata` requires. They were never importable, so this is not a regression; making them importable was explicitly out of scope.
- Working-directory `corpus_meta.json` files are unchanged on the wire (new fields are optional and omitted), so existing on-disk projects open unchanged.

---

### AD-21: One canonical `.corpuskit` storage location + bookmark rediscovery

**Status:** Accepted
**Date:** 2026-06-19 (Phase 1)

**Context:**
`CorpusPackage.swift` documented a `.corpuskit` layout (`project.json`, `chunking_config.json`, `export/`) that was never written — the real layout is the flat `WorkingDirectory` file set (`corpus_meta.json`, …). Worse, three path conventions diverged: the wizard and Open panel defaulted to `Documents/**CorpusKit**/<name>.corpuskit`, while `loadExistingWorkspaces` scanned `Documents/**CorpusKitStudio**/` and `WorkingDirectory.defaultLocation` used `Documents/**CorpusKitStudio**/<name>`. So wizard-created projects were never rediscovered on relaunch (wrong parent folder), and projects saved to arbitrary user-chosen locations were unreachable in a sandbox after the creating session.

**Decision:**
- **Doc comment corrected.** `CorpusPackage.swift` now documents the actual flat `WorkingDirectory` file set and notes that `ChunkingConfig` is in-memory/report-only and `ChapterConfig` is bundle-only.
- **One canonical location.** `WorkingDirectory` exposes `projectsRootURL` (container `Documents/CorpusKitStudio/`) as the single source of truth; the wizard default, the Open-panel default, and `defaultLocation` all use it. The legacy `Documents/CorpusKit/` folder is still **scanned** at launch (`legacyProjectsRootURL`) so older projects keep opening.
- **Security-scoped bookmarks for arbitrary locations.** New `ProjectBookmarkStore` persists `.withSecurityScope` bookmarks to a dedicated `ProjectBookmarks.plist` in Application Support (never `UserDefaults`), using the already-declared `com.apple.security.files.bookmarks.app-scope` entitlement. The wizard (`saveBookmark` after creation) and the Open-project flow (`saveBookmark` after load) record bookmarks; `loadExistingWorkspaces` resolves them at launch — refreshing stale ones, starting security-scoped access (tracked and balanced by `relinquishAll()` / `deinit`), and de-duplicating against the directory scan by path.

**Consequences:**
- A project created or opened anywhere is rediscovered on next launch: container projects via the canonical/legacy scan, user-chosen locations via bookmarks.
- Bookmarks are skipped for paths already under `projectsRootURL` (the scan covers them), so the bookmark file stays minimal.
- Default-location move from `Documents/CorpusKit` → `Documents/CorpusKitStudio` is not a regression: the old folder was never scanned before, and it is still scanned now for back-compat.
- **Verification note:** the metadata/schema and location-derivation logic is unit-tested (`defaultProjectLocationIsUnderCanonicalRoot` and the AD-20 tests). End-to-end bookmark rediscovery (create in the wizard at an external location → quit → relaunch → reappears) requires running the **sandboxed** app, since security-scoped bookmark resolution depends on the entitlement and container at runtime; it is not exercised by the unit-test bundle.

---

## Architectural decisions resolved (Phase 2)

These resolve the open questions from the AD walkthrough, tracked as Phase 2 in `PHASES.md` (2a–2c). Numbered here to match `PHASES.md`, not the AD-1…AD-21 snapshot above.

### P2a: `ProjectMetadata` removed as dead weight

**Status:** Accepted
**Date:** 2026-06-20 (Phase 2)

**Context:**
`ProjectMetadata` (in `EvalTypes.swift`) predated the AD-20 unification onto `CorpusMetadata`. An audit found it had **zero references** anywhere — not in CorpusKit, CorpusKitStudio, or the BigBookViaLLM consumer.

**Decision:** Removed the `public struct ProjectMetadata` (and its `CodingKeys`/init) entirely. `CorpusMetadata` (in CorpusKitStudio's `WorkingDirectory.swift`) is the single project-metadata type.

**Consequences:** No consumer change (the type was unused). Package and both consumers still build. This is a `public` API removal, acceptable because the only consumers are the two known local apps, both verified clean.

### P2b: `corpusAuthority` is a reserved multi-corpus field, intentionally inert

**Status:** Accepted
**Date:** 2026-06-20 (Phase 2)

**Context:**
`Chunk.corpusAuthority` is hardcoded to `1.0` by `UnifiedChunker` in both chunking paths and is **never read** by any search. Production retrieval (BigBookViaLLM `RAGEngine` → its `VectorStore` wrapper) ranks by **chapter weight** (`meta.chapterWeight(for:)`) passed as `VectorStore.search`'s `weightFunction`, not by `corpusAuthority`. The corpus-level `authorityWeight` (rank 1.5→0.6) lives in metadata and is likewise not pushed into `chunk.corpusAuthority`.

**Decision:** **Do not wire it; do not remove it.** `corpusAuthority` is reserved for future multi-corpus retrieval (the planned CorpusKit-for-Mac archive ranking across multiple corpora). Removing it would discard the design intent; wiring `authorityWeight → corpusAuthority` now would be untested dead code with no consumer. The working single-corpus ranking signal (`chapterWeight`) is the correct mechanism today. Intent is made explicit with comments at the two `UnifiedChunker` set-sites and at the `VectorStore.search()` weight computation.

**Consequences:** No behavior change. The field remains in the model and exported bundles, ready for multi-corpus ranking. When that lands, scoring multiplies `corpusAuthority` into the weighted score at the documented `VectorStore.search()` site.

### P2c: Eval harness embeds the question, not the expected passage

**Status:** Accepted
**Date:** 2026-06-20 (Phase 2)

**Context:**
`EvalRunner.run` embedded `test.expectedPassage` as the search vector. Production embeds the user's (expanded) **question**. Embedding the passage measures passage-vs-passage similarity, not the real query→chunk retrieval path — violating the "keep eval and production on identical paths" rule.

**Decision:** `EvalRunner` now embeds `test.question` (the `queryEmbedding`), used for both the vector search and the `SentenceRanker` call. The method signature is unchanged, so consumers (`EvalValidationService`) compile untouched.

**Consequences:** Eval scores now reflect real query→chunk retrieval. Existing thresholds were calibrated against passage-embedding and may need recalibration — that recalibration is **Phase 3 validation** against the real corpus. No unit test is added in the package because `EmbeddingService` needs the Core ML model resource (app-side only); `VectorStore` remains the package's tested surface.

---

*End of snapshot. AD-20/AD-21 resolved in Phase 1 (2026-06-19); Phase 2 (P2a–P2c) resolved 2026-06-20.*
