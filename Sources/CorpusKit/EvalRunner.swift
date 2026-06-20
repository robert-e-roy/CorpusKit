//
//  EvalRunner.swift
//  CorpusKit
//
//  Evaluation runner for testing retrieval quality
//

import Foundation

/// Protocol for chunks that can be evaluated (requires only text)
public protocol EvalChunk {
    var text: String { get }
}

/// Evaluation runner that uses VectorStore to test retrieval quality
public class EvalRunner {

    public init() {}

    /// Run evaluation tests against a set of chunks.
    /// Uses the same vector search path as consumer apps.
    public func run(
        tests: [EvalTest],
        items: [Chunk],
        embeddings: [[Float]],
        embeddingService: EmbeddingService,
        useSentenceRanking: Bool = false,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> [EvalResult] {

        let vectorStore = VectorStore<Chunk>()
        vectorStore.build(items: items, embeddings: embeddings)

        var results: [EvalResult] = []

        for (index, test) in tests.enumerated() {
            progressHandler?("Running test \(index + 1)/\(tests.count): \(test.question)")

            // Embed the question — matching the production retrieval path, which embeds the
            // user's query (not the expected passage). Phase 2c: keeps eval and production
            // on identical paths so eval scores reflect real query→chunk retrieval.
            let queryEmbedding = try await embeddingService.embed(test.question)
            let searchResults = vectorStore.search(query: queryEmbedding, k: 5)

            let retrievedChunks = searchResults.map { result in
                EvalResult.RetrievedChunkInfo(
                    chunkId: result.item.id,
                    text: result.item.text,
                    similarity: result.rawScore,
                    chapter: result.item.chapter,
                    page: result.item.page
                )
            }

            guard let topResult = searchResults.first else {
                results.append(EvalResult(
                    testId: test.id,
                    query: test.question,
                    expectedPassage: test.expectedPassage,
                    topMatch: "(no results)",
                    passed: false,
                    bestMatchSimilarity: 0.0,
                    threshold: test.matchThreshold,
                    retrievedChunks: []
                ))
                continue
            }

            var sentenceScore: Float? = nil
            var winningSentence: String? = nil
            var sentenceContext: String? = nil
            var sentenceChunkId: Int? = nil
            var sentenceCharacterOffset: Int? = nil
            var sentenceCharacterLength: Int? = nil

            if useSentenceRanking {
                let rankedSentences = try await SentenceRanker().rank(
                    query: queryEmbedding,
                    chunks: searchResults,
                    embeddingService: embeddingService
                )

                if let topSentence = rankedSentences.first {
                    sentenceScore = topSentence.score
                    winningSentence = topSentence.text
                    sentenceChunkId = topSentence.chunkID
                    sentenceCharacterOffset = topSentence.characterOffset
                    sentenceCharacterLength = topSentence.characterLength

                    var contextParts: [String] = []
                    if !topSentence.contextBefore.isEmpty { contextParts.append("[...] \(topSentence.contextBefore)") }
                    contextParts.append("→ \(topSentence.text)")
                    if !topSentence.contextAfter.isEmpty { contextParts.append("\(topSentence.contextAfter) [...]") }
                    sentenceContext = contextParts.joined(separator: " ")
                }
            }

            let effectiveScore = sentenceScore ?? topResult.rawScore
            let passed = effectiveScore >= test.matchThreshold

            results.append(EvalResult(
                testId: test.id,
                query: test.question,
                expectedPassage: test.expectedPassage,
                topMatch: String(topResult.item.text.prefix(100)),
                topMatchChunk: topResult.item.text,
                passed: passed,
                bestMatchSimilarity: topResult.rawScore,
                threshold: test.matchThreshold,
                retrievedChunks: retrievedChunks,
                timestamp: Date(),
                sentenceScore: sentenceScore,
                winningSentence: winningSentence,
                sentenceContext: sentenceContext,
                sentenceChunkId: sentenceChunkId,
                sentenceCharacterOffset: sentenceCharacterOffset,
                sentenceCharacterLength: sentenceCharacterLength
            ))
        }

        progressHandler?("Evaluation complete")
        return results
    }
}
