# CorpusKit Migration Checklist

Use this checklist to track the migration of both apps to CorpusKit.

## CorpusKitStudio Migration

### Pre-Migration
- [ ] Read INTEGRATION.md
- [ ] Read DIFFERENCES.md
- [ ] Back up current working state (git commit)
- [ ] Note current test results for comparison

### Package Integration
- [ ] Open CorpusKitStudio.xcodeproj in Xcode
- [ ] Add CorpusKit as local package dependency
  - Path: `/Users/robroy/Projects/CorpusKit`
- [ ] Verify package appears in project navigator
- [ ] Build project - should fail (expected)

### Code Changes

#### 1. Add CorpusKit Imports
- [ ] Add `import CorpusKit` to files that use EmbeddingService
- [ ] Add `import CorpusKit` to files that use VectorIndex

#### 2. Create EmbeddingService Wrapper
- [ ] Create new file: `EmbeddingServiceWrapper.swift`
- [ ] Copy wrapper code from INTEGRATION.md
- [ ] Update all `EmbeddingService` references to `EmbeddingServiceWrapper`
- [ ] Verify `@Observable` behavior still works

#### 3. Update VectorIndex to VectorStore
- [ ] Find all `VectorIndex` usage
- [ ] Replace with `VectorStore<Chunk>`
- [ ] Create chapter weight function (see INTEGRATION.md)
- [ ] Update `search()` calls to use weight function
- [ ] Update result handling (now returns `ScoredChunk<Chunk>`)

#### 4. Remove Old Files
- [ ] Delete `CorpusKitStudio/Pipeline/EmbeddingService.swift`
- [ ] Delete `CorpusKitStudio/Pipeline/VectorIndex.swift`
- [ ] Delete `CorpusKitStudio/Pipeline/WordPieceTokenizer.swift`
- [ ] Remove files from Xcode project (not just file system)

### Testing
- [ ] Build project (⌘B) - should succeed
- [ ] Run app
- [ ] Test embedding generation
  - [ ] Compare embedding values with old implementation
  - [ ] Verify L2 normalization (magnitude ≈ 1.0)
- [ ] Test vector search
  - [ ] Run same queries as before
  - [ ] Compare search results (ranking should match)
  - [ ] Verify scores are similar
- [ ] Test chapter weighting
  - [ ] Verify high-importance chapters rank higher
  - [ ] Compare with old weighting behavior
- [ ] Run unit tests (if any)
- [ ] Performance test (should be same or better)

### Post-Migration
- [ ] Git commit with message: "Migrate to CorpusKit package"
- [ ] Update documentation (if any references old structure)
- [ ] Note any issues or differences found

---

## BigBookViaLLM Migration

### Pre-Migration
- [ ] Read INTEGRATION.md
- [ ] Read DIFFERENCES.md
- [ ] Back up current working state (git commit)
- [ ] Note current test results for comparison

### Package Integration
- [ ] Open BigBookViaLLM.xcodeproj in Xcode
- [ ] Add CorpusKit as local package dependency
  - Path: `/Users/robroy/Projects/CorpusKit`
- [ ] Verify package appears in project navigator
- [ ] Build project - should fail (expected)

### Code Changes

#### 1. Add CorpusKit Imports
- [ ] Add `import CorpusKit` to files that use EmbeddingService
- [ ] Add `import CorpusKit` to files that use VectorStore

#### 2. Update EmbeddingService
- [ ] Replace `EmbeddingService` with `CorpusKit.EmbeddingService`
- [ ] Update all method calls (already async, should match)
- [ ] Verify model loading works (tests both .mlpackage and .mlmodelc)
- [ ] Verify vocab loading works (tests both .json and .txt)

#### 3. Create VectorStore Adapter
- [ ] Create new file: `VectorStoreAdapter.swift`
- [ ] Copy adapter code from INTEGRATION.md
- [ ] Replace all `VectorStore` references with `VectorStoreAdapter`
- [ ] Update result handling (adapter returns `[Chunk]` for compatibility)

#### 4. Remove Old Files
- [ ] Delete `BigBookViaLLM/Engine/EmbeddingService.swift`
- [ ] Delete `BigBookViaLLM/Engine/VectorStore.swift`
- [ ] Remove files from Xcode project (not just file system)

### Testing
- [ ] Build project (⌘B) - should succeed
- [ ] Run app on simulator
- [ ] Test corpus loading
  - [ ] Verify chunks load correctly
  - [ ] Verify embeddings load correctly
- [ ] Test embedding generation
  - [ ] Generate query embeddings
  - [ ] Compare with old implementation
  - [ ] Verify L2 normalization
- [ ] Test vector search
  - [ ] Run sample queries
  - [ ] Compare results with old implementation
  - [ ] Verify ranking matches
- [ ] Test on device (if possible)
- [ ] Run unit tests (if any)
- [ ] Performance test

### Post-Migration
- [ ] Git commit with message: "Migrate to CorpusKit package"
- [ ] Update documentation
- [ ] Note any issues or differences found

---

## Both Apps

### Final Verification
- [ ] CorpusKitStudio builds and runs ✅
- [ ] BigBookViaLLM builds and runs ✅
- [ ] Search results match between apps (same corpus, same queries)
- [ ] Performance is acceptable
- [ ] No crashes or memory leaks

### Cleanup
- [ ] Review old git history for any notes/TODOs
- [ ] Update README files if they reference old structure
- [ ] Archive old implementations (keep in git history)

---

## Rollback Plan

If issues are found:

1. **Don't delete old files immediately**
   - Keep them in a backup folder first
   - Only delete after 1 week of successful operation

2. **Git revert**
   - All changes are in git
   - Can revert to pre-migration state

3. **Gradual migration**
   - Can migrate one component at a time
   - Start with just EmbeddingService
   - Then VectorStore after testing

---

## Success Criteria

Migration is successful when:

- ✅ Both apps build without errors
- ✅ Both apps run without crashes
- ✅ Search results match original implementations
- ✅ Performance is equivalent or better
- ✅ All tests pass
- ✅ No memory leaks or resource issues
- ✅ Code is cleaner and more maintainable

---

## Troubleshooting

### Build Errors

**"No such module 'CorpusKit'"**
- Verify package was added correctly in Xcode
- Try cleaning build folder (⌘⇧K)
- Restart Xcode

**"Cannot find type 'VectorStore' in scope"**
- Check import statement: `import CorpusKit`
- Verify package is listed under target dependencies

### Runtime Errors

**"Model not found"**
- Verify MiniLMEmbedding.mlpackage is in Copy Bundle Resources
- Check Build Phases → Copy Bundle Resources

**"Vocabulary not found"**
- Verify vocab.json or vocab.txt is in bundle
- Check file extension matches what's bundled

### Search Quality Issues

**Different results than before**
- Compare raw scores vs weighted scores
- Verify weight function logic matches old implementation
- Check that embeddings are still normalized (magnitude ≈ 1.0)
- Use debug logging to trace score calculations

**Performance regression**
- Profile with Instruments
- Verify vDSP is being used (not fallback)
- Check for unnecessary array copies

---

## Notes

- Take your time with each step
- Test thoroughly at each stage
- Keep old code until fully verified
- Document any unexpected differences
- Ask for help if needed

---

## Estimated Time

- **CorpusKitStudio**: 1-2 hours
- **BigBookViaLLM**: 1-2 hours
- **Testing both**: 2-3 hours
- **Total**: 4-7 hours

Plan for a full day to be safe.
