# CorpusKit Documentation Index

This document provides a guide to all documentation files in the CorpusKit package.

## Getting Started (Read First)

### 1. [README.md](README.md)
**Start here** - Overview of the package, features, and basic usage examples.

**Topics covered:**
- What is CorpusKit?
- Key features
- Installation instructions
- Basic usage examples
- Platform requirements

**Read time:** 5 minutes

### 2. [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
**Quick lookup** - Common code patterns and usage examples.

**Topics covered:**
- Setup code snippets
- Search patterns
- Error handling
- Observable wrapper pattern
- Adapter pattern
- Debugging tips

**Read time:** 3 minutes

## Implementation Details

### 3. [SUMMARY.md](SUMMARY.md)
**Project overview** - High-level summary of what was created and why.

**Topics covered:**
- Package structure
- What was extracted from each app
- Key design decisions
- Benefits and risks
- Next steps

**Read time:** 5 minutes

### 4. [DIFFERENCES.md](DIFFERENCES.md)
**Technical analysis** - Detailed comparison of the two original implementations.

**Topics covered:**
- EmbeddingService differences
- VectorStore/VectorIndex differences
- Chunk model differences
- Chapter weighting differences
- Design decision rationales

**Read time:** 10 minutes
**Audience:** Developers who want to understand the consolidation decisions

## Migration Guides

### 5. [INTEGRATION.md](INTEGRATION.md)
**Step-by-step guide** - How to integrate CorpusKit into both apps.

**Topics covered:**
- Adding package dependency in Xcode
- Code changes for CorpusKitStudio
- Code changes for BigBookViaLLM
- Files to delete
- Testing checklist
- Troubleshooting

**Read time:** 15 minutes
**Audience:** Developers performing the migration

### 6. [MIGRATION_CHECKLIST.md](MIGRATION_CHECKLIST.md)
**Detailed checklist** - Track migration progress step by step.

**Topics covered:**
- Pre-migration preparation
- CorpusKitStudio migration steps
- BigBookViaLLM migration steps
- Testing verification
- Rollback plan
- Success criteria

**Read time:** Use as reference during migration
**Audience:** Developers performing the migration

## Code Documentation

### Source Files

**[Sources/CorpusKit/EmbeddingService.swift](Sources/CorpusKit/EmbeddingService.swift)**
- MiniLM-L6-v2 embedding generation
- L2 normalization
- Batch processing
- 384-dimensional vectors

**[Sources/CorpusKit/VectorStore.swift](Sources/CorpusKit/VectorStore.swift)**
- Generic vector similarity search
- vDSP-accelerated dot product
- Custom weight functions
- Structured result types

**[Sources/CorpusKit/WordPieceTokenizer.swift](Sources/CorpusKit/WordPieceTokenizer.swift)**
- BERT-style tokenization
- JSON and TXT vocab support
- WordPiece algorithm

### Test Files

**[Tests/CorpusKitTests/CorpusKitTests.swift](Tests/CorpusKitTests/CorpusKitTests.swift)**
- Basic search test
- Weighted search test
- 2 tests, all passing

## Quick Navigation

### I want to...

**...understand what CorpusKit does**
→ Read [README.md](README.md)

**...see code examples**
→ Read [QUICK_REFERENCE.md](QUICK_REFERENCE.md)

**...integrate it into an app**
→ Read [INTEGRATION.md](INTEGRATION.md) and use [MIGRATION_CHECKLIST.md](MIGRATION_CHECKLIST.md)

**...understand design decisions**
→ Read [DIFFERENCES.md](DIFFERENCES.md) and [SUMMARY.md](SUMMARY.md)

**...troubleshoot an issue**
→ Check [INTEGRATION.md](INTEGRATION.md) § Troubleshooting

**...understand the migration impact**
→ Read [SUMMARY.md](SUMMARY.md) § Risks

**...verify the package works**
```bash
cd /Users/robroy/Projects/CorpusKit
swift build && swift test
```

## Document Status

| Document | Status | Last Updated |
|----------|--------|--------------|
| README.md | ✅ Complete | 2026-05-02 |
| QUICK_REFERENCE.md | ✅ Complete | 2026-05-02 |
| SUMMARY.md | ✅ Complete | 2026-05-02 |
| DIFFERENCES.md | ✅ Complete | 2026-05-02 |
| INTEGRATION.md | ✅ Complete | 2026-05-02 |
| MIGRATION_CHECKLIST.md | ✅ Complete | 2026-05-02 |
| INDEX.md | ✅ Complete | 2026-05-02 |

## Package Files

```
CorpusKit/
├── Documentation/
│   ├── INDEX.md                       ← You are here
│   ├── README.md                      ← Start here
│   ├── QUICK_REFERENCE.md             ← Quick lookup
│   ├── SUMMARY.md                     ← Project overview
│   ├── DIFFERENCES.md                 ← Technical analysis
│   ├── INTEGRATION.md                 ← Migration guide
│   └── MIGRATION_CHECKLIST.md         ← Migration checklist
│
├── Package.swift                      ← Swift Package manifest
│
├── Sources/CorpusKit/
│   ├── EmbeddingService.swift         ← Embedding generation
│   ├── VectorStore.swift              ← Vector search
│   └── WordPieceTokenizer.swift       ← BERT tokenization
│
└── Tests/CorpusKitTests/
    └── CorpusKitTests.swift           ← Unit tests
```

## Need Help?

1. Check the documentation index above
2. Search this repo for relevant examples
3. Review the test files for usage patterns
4. Check INTEGRATION.md troubleshooting section

## Contributing

This is a shared package between two apps:
- **CorpusKitStudio** (macOS)
- **BigBookViaLLM** (iOS)

Changes should be tested in both apps before committing.

## Version

**Current**: 1.0.0 (initial release)
**Created**: 2026-05-02
**Swift**: 5.9+
**Platforms**: iOS 17+, macOS 14+
