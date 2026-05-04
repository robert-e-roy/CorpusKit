//
//  WordPieceTokenizer.swift
//  CorpusKit
//
//  Production-quality WordPiece tokenizer for BERT-style models
//

import Foundation

/// WordPiece tokenizer compatible with BERT vocabulary files
/// Supports both .json ({"token": id}) and .txt (line-delimited) formats
class WordPieceTokenizer {

    private let vocab: [String: Int]
    private let clsToken = "[CLS]"
    private let sepToken = "[SEP]"
    private let padToken = "[PAD]"
    private let unkToken = "[UNK]"

    /// Initialize tokenizer from vocabulary file
    /// - Parameter vocabURL: URL to vocab.json or vocab.txt
    /// - Throws: TokenizerError if vocabulary is invalid or cannot be loaded
    init(vocabURL: URL) throws {
        let fileExtension = vocabURL.pathExtension

        if fileExtension == "json" {
            // Load JSON format: {"[PAD]": 0, "word": 123, ...}
            let data = try Data(contentsOf: vocabURL)
            self.vocab = try JSONDecoder().decode([String: Int].self, from: data)
        } else {
            // Load TXT format: line-delimited tokens
            let content = try String(contentsOf: vocabURL, encoding: .utf8)
            var vocabDict: [String: Int] = [:]

            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    vocabDict[token] = index
                }
            }

            guard !vocabDict.isEmpty else {
                throw TokenizerError.vocabLoadFailed
            }

            self.vocab = vocabDict
        }

        // Verify required tokens exist
        guard vocab[unkToken] != nil,
              vocab[clsToken] != nil,
              vocab[sepToken] != nil,
              vocab[padToken] != nil else {
            throw TokenizerError.invalidVocabulary
        }
    }

    /// Tokenize text into token IDs and attention mask
    /// - Parameters:
    ///   - text: Input text to tokenize
    ///   - maxLength: Maximum sequence length (default: 128)
    /// - Returns: Tuple of (ids, mask) arrays
    func tokenize(_ text: String, maxLength: Int = 128) -> (ids: [Int], mask: [Int]) {
        var tokenIds: [Int] = []

        // Add [CLS] token
        tokenIds.append(vocab[clsToken]!)

        // Tokenize each word
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for word in words {
            let wordTokens = tokenizeWord(word)
            tokenIds.append(contentsOf: wordTokens)

            // Stop if we're approaching max length (leave room for [SEP])
            if tokenIds.count >= maxLength - 1 {
                break
            }
        }

        // Add [SEP] token
        tokenIds.append(vocab[sepToken]!)

        // Truncate if needed
        if tokenIds.count > maxLength {
            tokenIds = Array(tokenIds.prefix(maxLength - 1))
            tokenIds.append(vocab[sepToken]!)
        }

        // Create attention mask (1 for real tokens, 0 for padding)
        var mask = [Int](repeating: 1, count: tokenIds.count)

        // Pad to max length
        let padId = vocab[padToken]!
        while tokenIds.count < maxLength {
            tokenIds.append(padId)
            mask.append(0)
        }

        return (ids: tokenIds, mask: mask)
    }

    /// WordPiece algorithm: greedily match longest subword from vocabulary
    private func tokenizeWord(_ word: String) -> [Int] {
        var tokens: [Int] = []
        var start = word.startIndex

        while start < word.endIndex {
            var end = word.endIndex
            var found = false

            // Try progressively shorter substrings
            while start < end {
                let substring = String(word[start..<end])
                let token = start == word.startIndex ? substring : "##\(substring)"

                if let id = vocab[token] {
                    tokens.append(id)
                    start = end
                    found = true
                    break
                }

                // Try shorter substring
                end = word.index(before: end)
            }

            // If no match found, use [UNK]
            if !found {
                tokens.append(vocab[unkToken]!)
                start = word.index(after: start)
            }
        }

        return tokens
    }

    enum TokenizerError: Error, LocalizedError {
        case invalidVocabulary
        case vocabLoadFailed

        var errorDescription: String? {
            switch self {
            case .invalidVocabulary:
                return "Vocabulary file missing required tokens ([CLS], [SEP], [UNK], [PAD])"
            case .vocabLoadFailed:
                return "Failed to load vocabulary file"
            }
        }
    }
}
