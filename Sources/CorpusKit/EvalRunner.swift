//
//  EvalRunner.swift
//  CorpusKit
//
//  Evaluation runner for testing retrieval quality
//

import Foundation

/// Result of a single evaluation test
public struct EvalResult: Codable {
    public let testID: String
    public let query: String
    public let expectedPassage: String
    public let score: Float
    public let threshold: Float
    public let topMatch: String
    public let topMatchChunk: String?
    public let timestamp: Date

    // Sentence-level scoring (optional, populated when sentence ranking is used)
    public let sentenceScore: Float?
    public let winningSentence: String?
    public let sentenceContext: String?
    public let sentenceChunkId: Int?
    public let sentenceCharacterOffset: Int?
    public let sentenceCharacterLength: Int?

    public var passed: Bool { score >= threshold }

    enum CodingKeys: String, CodingKey {
        case testID = "test_id"
        case query
        case expectedPassage = "expected_passage"
        case score
        case threshold
        case topMatch = "top_match"
        case topMatchChunk = "top_match_chunk"
        case timestamp
        case sentenceScore = "sentence_score"
        case winningSentence = "winning_sentence"
        case sentenceContext = "sentence_context"
        case sentenceChunkId = "sentence_chunk_id"
        case sentenceCharacterOffset = "sentence_character_offset"
        case sentenceCharacterLength = "sentence_character_length"
    }

    public init(
        testID: String,
        query: String,
        expectedPassage: String,
        score: Float,
        threshold: Float,
        topMatch: String,
        topMatchChunk: String? = nil,
        timestamp: Date = Date(),
        sentenceScore: Float? = nil,
        winningSentence: String? = nil,
        sentenceContext: String? = nil,
        sentenceChunkId: Int? = nil,
        sentenceCharacterOffset: Int? = nil,
        sentenceCharacterLength: Int? = nil
    ) {
        self.testID = testID
        self.query = query
        self.expectedPassage = expectedPassage
        self.score = score
        self.threshold = threshold
        self.topMatch = topMatch
        self.topMatchChunk = topMatchChunk
        self.timestamp = timestamp
        self.sentenceScore = sentenceScore
        self.winningSentence = winningSentence
        self.sentenceContext = sentenceContext
        self.sentenceChunkId = sentenceChunkId
        self.sentenceCharacterOffset = sentenceCharacterOffset
        self.sentenceCharacterLength = sentenceCharacterLength
    }
}

/// Evaluation test definition
public struct EvalTest: Codable {
    public let id: String
    public let question: String
    public let expectedPassage: String
    public let matchThreshold: Float

    enum CodingKeys: String, CodingKey {
        case id
        case question
        case expectedPassage = "expected_passage"
        case matchThreshold = "match_threshold"
    }

    public init(id: String, question: String, expectedPassage: String, matchThreshold: Float) {
        self.id = id
        self.question = question
        self.expectedPassage = expectedPassage
        self.matchThreshold = matchThreshold
    }
}

/// Generic chunk protocol for evaluation
public protocol EvalChunk {
    var text: String { get }
}

/// Evaluation runner that uses VectorStore to test retrieval quality
public class EvalRunner {

    public init() {}

    /// Run evaluation tests using the vector store with optional sentence ranking
    /// - Parameters:
    ///   - tests: Array of evaluation tests
    ///   - items: Array of chunks/items to search
    ///   - embeddings: Pre-computed embeddings matching items
    ///   - embeddingService: Service to embed test passages
    ///   - useSentenceRanking: Whether to use sentence-level ranking (default: false)
    ///   - progressHandler: Optional progress callback
    /// - Returns: Array of evaluation results
    public func run<T: EvalChunk & RankableChunk>(
        tests: [EvalTest],
        items: [T],
        embeddings: [[Float]],
        embeddingService: EmbeddingService,
        useSentenceRanking: Bool = false,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> [EvalResult] {

        // Build vector store
        let vectorStore = VectorStore<T>()
        vectorStore.build(items: items, embeddings: embeddings)

        var results: [EvalResult] = []

        for (index, test) in tests.enumerated() {
            progressHandler?("Running test \(index + 1)/\(tests.count): \(test.question)")

            // Embed the expected passage (not the question!)
            let passageEmbedding = try await embeddingService.embed(test.expectedPassage)

            // Search for similar chunks
            let searchResults = vectorStore.search(query: passageEmbedding, k: 5)

            // Get top match
            guard let topResult = searchResults.first else {
                results.append(EvalResult(
                    testID: test.id,
                    query: test.question,
                    expectedPassage: test.expectedPassage,
                    score: 0.0,
                    threshold: test.matchThreshold,
                    topMatch: "(no results)",
                    topMatchChunk: nil
                ))
                continue
            }

            // Sentence-level scoring if requested
            var sentenceScore: Float? = nil
            var winningSentence: String? = nil
            var sentenceContext: String? = nil

            if useSentenceRanking {
                let sentenceRanker = SentenceRanker()
                let rankedSentences = try await sentenceRanker.rank(
                    query: passageEmbedding,
                    chunks: searchResults,
                    embeddingService: embeddingService
                )

                if let topSentence = rankedSentences.first {
                    sentenceScore = topSentence.score
                    winningSentence = topSentence.text

                    // Build context string
                    var contextParts: [String] = []
                    if !topSentence.contextBefore.isEmpty {
                        contextParts.append("[...] \(topSentence.contextBefore)")
                    }
                    contextParts.append("→ \(topSentence.text)")
                    if !topSentence.contextAfter.isEmpty {
                        contextParts.append("\(topSentence.contextAfter) [...]")
                    }
                    sentenceContext = contextParts.joined(separator: " ")
                }
            }

            // Create result
            let result = EvalResult(
                testID: test.id,
                query: test.question,
                expectedPassage: test.expectedPassage,
                score: topResult.rawScore,
                threshold: test.matchThreshold,
                topMatch: String(topResult.item.text.prefix(100)),
                topMatchChunk: topResult.item.text,
                sentenceScore: sentenceScore,
                winningSentence: winningSentence,
                sentenceContext: sentenceContext
            )

            results.append(result)
        }

        progressHandler?("Evaluation complete")

        return results
    }
}
