//
//  SentenceRanker.swift
//  CorpusKit
//
//  Ranks sentences within retrieved chunks to find the most relevant sentence
//  Returns character offsets for precise highlighting in original text
//

import Accelerate
import Foundation

/// A ranked sentence with its location and context
public struct RankedSentence {
    public let text: String
    public let score: Float
    public let chunkID: Int
    public let characterOffset: Int      // offset within chunk text
    public let characterLength: Int      // for highlight range
    public let contextBefore: String     // 1 sentence before
    public let contextAfter: String      // 1 sentence after

    public init(
        text: String,
        score: Float,
        chunkID: Int,
        characterOffset: Int,
        characterLength: Int,
        contextBefore: String,
        contextAfter: String
    ) {
        self.text = text
        self.score = score
        self.chunkID = chunkID
        self.characterOffset = characterOffset
        self.characterLength = characterLength
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

/// Protocol for chunks that can be used with SentenceRanker
public protocol RankableChunk {
    var id: Int { get }
    var text: String { get }
}

/// Ranks sentences within chunks to find the most relevant sentence per chunk
public class SentenceRanker {

    private struct Sentence {
        let text: String
        let startOffset: Int
        let length: Int
    }

    public init() {}

    /// Rank sentences within retrieved chunks to find the best sentence per chunk
    /// - Parameters:
    ///   - query: Query embedding vector (L2-normalized)
    ///   - chunks: Retrieved chunks to rank sentences within
    ///   - embeddingService: Service for embedding sentences
    /// - Returns: Array of ranked sentences, one per chunk (highest scoring first)
    public func rank<T: RankableChunk>(
        query: [Float],
        chunks: [ScoredChunk<T>],
        embeddingService: EmbeddingService
    ) async throws -> [RankedSentence] {

        var rankedSentences: [RankedSentence] = []

        for scoredChunk in chunks {
            let chunk = scoredChunk.item

            // Split chunk into sentences
            let sentences = splitIntoSentences(chunk.text)

            // Filter sentences by minimum word count
            let validSentences = sentences.filter { sentence in
                let wordCount = sentence.text.split(separator: " ").count
                return wordCount >= 5  // Minimum 5 words
            }

            // Limit to 20 sentences to bound embedding cost
            let sentencesToRank = Array(validSentences.prefix(20))

            guard !sentencesToRank.isEmpty else {
                continue
            }

            // Embed all sentences
            let sentenceTexts = sentencesToRank.map { $0.text }
            let sentenceEmbeddings = try await embeddingService.embedBatch(sentenceTexts)

            // Score each sentence against query
            var bestScore: Float = 0
            var bestSentenceIndex: Int = 0

            for (index, embedding) in sentenceEmbeddings.enumerated() {
                var similarity: Float = 0
                vDSP_dotpr(
                    query, 1,
                    embedding, 1,
                    &similarity,
                    vDSP_Length(query.count)
                )

                if similarity > bestScore {
                    bestScore = similarity
                    bestSentenceIndex = index
                }
            }

            // Get the best sentence and its context
            let bestSentence = sentencesToRank[bestSentenceIndex]

            // Find context sentences
            let allSentencesInChunk = sentences
            let bestSentenceIndexInAll = allSentencesInChunk.firstIndex { $0.startOffset == bestSentence.startOffset } ?? 0

            let contextBefore: String
            if bestSentenceIndexInAll > 0 {
                contextBefore = allSentencesInChunk[bestSentenceIndexInAll - 1].text
            } else {
                contextBefore = ""
            }

            let contextAfter: String
            if bestSentenceIndexInAll < allSentencesInChunk.count - 1 {
                contextAfter = allSentencesInChunk[bestSentenceIndexInAll + 1].text
            } else {
                contextAfter = ""
            }

            // Create ranked sentence
            let rankedSentence = RankedSentence(
                text: bestSentence.text,
                score: bestScore,
                chunkID: chunk.id,
                characterOffset: bestSentence.startOffset,
                characterLength: bestSentence.length,
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )

            rankedSentences.append(rankedSentence)
        }

        // Sort by score descending
        return rankedSentences.sorted { $0.score > $1.score }
    }

    // MARK: - Private Helpers

    /// Split text into sentences preserving their offsets
    private func splitIntoSentences(_ text: String) -> [Sentence] {
        var sentences: [Sentence] = []
        var currentStart = 0
        var currentSentence = ""

        for (index, char) in text.enumerated() {
            currentSentence.append(char)

            // Check for sentence boundaries: . ? ! followed by whitespace or end of text
            if char == "." || char == "?" || char == "!" {
                let nextIndex = text.index(text.startIndex, offsetBy: index + 1)
                let isEndOfText = nextIndex >= text.endIndex
                let isFollowedByWhitespace = !isEndOfText && text[nextIndex].isWhitespace

                if isEndOfText || isFollowedByWhitespace {
                    // Trim whitespace
                    let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sentences.append(Sentence(
                            text: trimmed,
                            startOffset: currentStart,
                            length: trimmed.utf8.count
                        ))
                    }

                    // Reset for next sentence
                    currentSentence = ""
                    currentStart = index + 1

                    // Skip whitespace after sentence boundary
                    while currentStart < text.count {
                        let idx = text.index(text.startIndex, offsetBy: currentStart)
                        if idx < text.endIndex && text[idx].isWhitespace {
                            currentStart += 1
                        } else {
                            break
                        }
                    }
                }
            }
        }

        // Add remaining text as final sentence if not empty
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(Sentence(
                text: trimmed,
                startOffset: currentStart,
                length: trimmed.utf8.count
            ))
        }

        return sentences
    }
}
