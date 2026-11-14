# Phase 4a — Claude Code Handoff: Embedding Consolidation

## Context
PHASES.md (attached) is the source of truth. Phase 4a model artifact is complete:
- `arctic-embed-m-v1.5.mlmodelc` (416 MB) compiled and verified
- Replaces `all-MiniLM-L6-v2` — dimension changes 384 → 768
- Metadata: model_id, dimension=768, seq_length=256, pooling=mean, normalised=true

## Decisions already made — do not re-litigate
- **Single CorpusKit target (Option A):** EmbeddingService stays in CorpusKit — no new
  CorpusKitEmbedding target. Moving it would break BigBookViaLLM's `import CorpusKit`.
- **neuralnetwork format** (not mlprogram) — libmilstoragepython unavailable in coremltools 6.3
- **seq_length=256** is the fixed sequence length the model was traced at

## Work to complete

### Phase A — Bundle Arctic in the CorpusKit target
1. Copy `arctic-embed-m-v1.5.mlmodelc` into `CorpusKit/Sources/CorpusKit/Resources/`
2. In `Package.swift`: add `.copy("Resources/arctic-embed-m-v1.5.mlmodelc")` and
   `.copy("Resources/vocab.txt")` to the CorpusKit target — must be `.copy` not `.process`
3. In `EmbeddingService.load()`:
   - Resolve model via `Bundle.module` first, fall back to `Bundle.main`
   - Read `seq_length` from model metadata (`MLModelMetadataKey(rawValue: "seq_length")`)
     with fallback to 256 — do not hardcode the sequence length
4. Delete per-app model resource copies from CorpusKit Studio — verify build still passes
5. Do NOT touch BigBookViaLLM — it keeps its own copy as Bundle.main fallback for now
6. Configure Git LFS for `*.mlmodelc` before first commit of the model binary

### Phase B — Model identity & compatibility
7. Add to CorpusKit package:
   ```swift
   public struct EmbeddingModelInfo {
       public let id: String
       public let dimension: Int
       public let seqLength: Int
       public let revision: Int
   }
   ```
8. Replace all hardcoded `384` dimension literals — Arctic is 768.
   Replace all `embedding_model: "all-MiniLM-L6-v2"` and `embedding_dimension: 384`
   export values with values derived from `EmbeddingModelInfo`
9. Add compatibility guard at corpus load: compare `corpus_meta.json` fields
   `embedding_model` and `embedding_dimension` against the loaded model's
   `EmbeddingModelInfo`. Refuse to load (throw a clear error) on mismatch.
   This is the safety net when models are swapped in future.

### Phase B bonus — embedding unit tests
10. Now that the model resolves via `Bundle.module`, add XCTest embedding tests to the
    CorpusKit package:
    - Same sentence embedded twice → identical vectors
    - Two different sentences → cosine similarity < 1.0
    - Output dimension == 768
    - Verify mean pooling with attention mask (embed a short sentence padded to seq_length,
      confirm result differs from embedding without masking)

## Deliver as one PR: Phase A + B together

## Rules
- Only show changed files
- Do not modify RAGEngine.swift or any BigBookViaLLM files
- All corpora must be re-embedded after this PR merges (dimension 384 → 768)
