//
//  EvalTypes.swift
//  CorpusKit
//
//  Canonical eval and corpus metadata types shared between CorpusKitStudio and consumer apps.
//

import Foundation

// MARK: - Evaluation Tests

public struct EvalTest: Codable, Identifiable {
    public var id: String
    public var question: String
    public var expectedPassage: String
    public var expectedChapter: String?
    public var matchThreshold: Float
    public var isEnabled: Bool

    public enum CodingKeys: String, CodingKey {
        case id
        case question
        case expectedPassage = "expected_passage"
        case expectedChapter = "expected_chapter"
        case matchThreshold = "match_threshold"
        case isEnabled = "is_enabled"
    }

    public init(
        id: String? = nil,
        question: String,
        expectedPassage: String,
        expectedChapter: String? = nil,
        matchThreshold: Float = 0.75,
        isEnabled: Bool = true
    ) {
        self.expectedPassage = expectedPassage
        self.expectedChapter = expectedChapter
        self.matchThreshold = matchThreshold
        self.isEnabled = isEnabled
        if let providedId = id {
            self.id = providedId
            self.question = question
        } else {
            self.id = question.isEmpty ? UUID().uuidString : Self.slugify(question)
            self.question = question
        }
    }

    public static func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet.whitespaces)
        let cleaned = text.lowercased()
            .components(separatedBy: allowed.inverted)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return String(cleaned.prefix(50))
    }
}

public struct EvalTests: Codable {
    public var tests: [EvalTest]

    public init(tests: [EvalTest] = []) {
        self.tests = tests
    }
}

// MARK: - Evaluation Results

public struct EvalResult: Codable {
    public let testId: String
    public let query: String
    public let expectedPassage: String
    public let topMatch: String
    public let topMatchChunk: String?
    public let passed: Bool
    public let bestMatchSimilarity: Float
    public let threshold: Float
    public let retrievedChunks: [RetrievedChunkInfo]
    public let timestamp: Date

    public let sentenceScore: Float?
    public let winningSentence: String?
    public let sentenceContext: String?
    public let sentenceChunkId: Int?
    public let sentenceCharacterOffset: Int?
    public let sentenceCharacterLength: Int?

    public struct RetrievedChunkInfo: Codable {
        public let chunkId: Int
        public let text: String
        public let similarity: Float
        public let chapter: String
        public let page: Int

        public enum CodingKeys: String, CodingKey {
            case chunkId = "chunk_id"
            case text
            case similarity
            case chapter
            case page
        }

        public init(chunkId: Int, text: String, similarity: Float, chapter: String, page: Int) {
            self.chunkId = chunkId
            self.text = text
            self.similarity = similarity
            self.chapter = chapter
            self.page = page
        }
    }

    public enum CodingKeys: String, CodingKey {
        case testId = "test_id"
        case query
        case expectedPassage = "expected_passage"
        case topMatch = "top_match"
        case topMatchChunk = "top_match_chunk"
        case passed
        case bestMatchSimilarity = "score"
        case threshold
        case retrievedChunks = "retrieved_chunks"
        case timestamp
        case sentenceScore = "sentence_score"
        case winningSentence = "winning_sentence"
        case sentenceContext = "sentence_context"
        case sentenceChunkId = "sentence_chunk_id"
        case sentenceCharacterOffset = "sentence_character_offset"
        case sentenceCharacterLength = "sentence_character_length"
    }

    public init(
        testId: String,
        query: String,
        expectedPassage: String,
        topMatch: String,
        topMatchChunk: String? = nil,
        passed: Bool,
        bestMatchSimilarity: Float,
        threshold: Float,
        retrievedChunks: [RetrievedChunkInfo] = [],
        timestamp: Date = Date(),
        sentenceScore: Float? = nil,
        winningSentence: String? = nil,
        sentenceContext: String? = nil,
        sentenceChunkId: Int? = nil,
        sentenceCharacterOffset: Int? = nil,
        sentenceCharacterLength: Int? = nil
    ) {
        self.testId = testId
        self.query = query
        self.expectedPassage = expectedPassage
        self.topMatch = topMatch
        self.topMatchChunk = topMatchChunk
        self.passed = passed
        self.bestMatchSimilarity = bestMatchSimilarity
        self.threshold = threshold
        self.retrievedChunks = retrievedChunks
        self.timestamp = timestamp
        self.sentenceScore = sentenceScore
        self.winningSentence = winningSentence
        self.sentenceContext = sentenceContext
        self.sentenceChunkId = sentenceChunkId
        self.sentenceCharacterOffset = sentenceCharacterOffset
        self.sentenceCharacterLength = sentenceCharacterLength
    }
}

// MARK: - Evaluation Summary

public struct EvalSummary {
    public let totalTests: Int
    public let passedTests: Int
    public let failedTests: Int
    public let results: [EvalResult]

    public var passRate: Double {
        guard totalTests > 0 else { return 0 }
        return Double(passedTests) / Double(totalTests)
    }

    public var allPassed: Bool { failedTests == 0 }

    public init(results: [EvalResult]) {
        self.results = results
        self.totalTests = results.count
        self.passedTests = results.filter { $0.passed }.count
        self.failedTests = results.filter { !$0.passed }.count
    }
}
