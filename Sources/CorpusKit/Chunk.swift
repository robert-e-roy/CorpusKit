//
//  Chunk.swift
//  CorpusKit
//
//  Created by Robert Roy on 4/17/26.
//


import Foundation

public struct Chunk: Codable, Identifiable, EvalChunk, RankableChunk {
    public var id: Int   // reassigned when chunks are renumbered after (re)chunking
    public var text: String
    public let source: String
    public var chapter: String
    public var page: Int                 // Primary display page (uses bookPage if available, else pdfPage)
    public var pdfPage: Int?             // PDF index for debugging
    public var bookPage: Int?            // Extracted printed page number from PDF content or estimated page for EPUB
    public var pageNumberSource: String? // "extracted", "inherited", "fallback", or "estimated"
    public var pageConfidence: String?   // "high" (extracted/chapter_start) or "low" (estimated)
    public var paragraph: Int?           // EPUB: paragraph number within chapter (reflowable format)
    public var sourceFile: String?       // EPUB: source XHTML file name
    public var wordStart: Int
    public var wordEnd: Int
    public var importance: Float         // chunk-level, curator-set, 0.0-1.0
    public var corpusAuthority: Float    // corpus-level authority weight, 0.0-2.0
    public var usageScore: Float?        // from server feedback, nil if not yet available
    public var embedding: [Float]?       // populated after embedding step
    public var characterOffsetInChapter: Int? // Character position where this chunk begins within the full chapter text

    // Sentence-level highlighting — transient, never persisted to chunks.json
    public var winningSentence: String?           // The best matching sentence within this chunk
    public var sentenceScore: Float?              // Similarity score of the winning sentence
    public var sentenceCharacterOffset: Int?      // Character offset of sentence within chunk text
    public var sentenceCharacterLength: Int?      // Length of sentence for highlighting

    // Excluded from serialization — sentence fields are ephemeral eval state
    public enum CodingKeys: String, CodingKey {
        case id, text, source, chapter, page, pdfPage, bookPage
        case pageNumberSource, pageConfidence, paragraph, sourceFile
        case wordStart, wordEnd, importance, corpusAuthority, usageScore
        case embedding, characterOffsetInChapter
    }

    public init(
        id: Int,
        text: String,
        source: String,
        chapter: String,
        page: Int,
        pdfPage: Int? = nil,
        bookPage: Int? = nil,
        pageNumberSource: String? = nil,
        pageConfidence: String? = nil,
        paragraph: Int? = nil,
        sourceFile: String? = nil,
        wordStart: Int,
        wordEnd: Int,
        importance: Float,
        corpusAuthority: Float,
        usageScore: Float? = nil,
        embedding: [Float]? = nil,
        characterOffsetInChapter: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.chapter = chapter
        self.page = page
        self.pdfPage = pdfPage
        self.bookPage = bookPage
        self.pageNumberSource = pageNumberSource
        self.pageConfidence = pageConfidence
        self.paragraph = paragraph
        self.sourceFile = sourceFile
        self.wordStart = wordStart
        self.wordEnd = wordEnd
        self.importance = importance
        self.corpusAuthority = corpusAuthority
        self.usageScore = usageScore
        self.embedding = embedding
        self.characterOffsetInChapter = characterOffsetInChapter
        self.winningSentence = nil
        self.sentenceScore = nil
        self.sentenceCharacterOffset = nil
        self.sentenceCharacterLength = nil
    }

    // Display location for UI (includes the chapter)
    public var displayLocation: String {
        if let para = paragraph {
            return "\(chapter) ¶\(para)"
        } else {
            // For estimated pages, show with tilde prefix
            let prefix = (pageConfidence == "low" && pageNumberSource == "estimated") ? "~" : ""
            return "\(prefix)p.\(page)"
        }
    }

    /// Page-only label for views that already show the chapter separately. Shows the printed book
    /// page when available (`~` prefix flags a low-confidence EPUB estimate) and, for reflowable
    /// EPUB, also the paragraph marker — e.g. "~p.12 ¶27", "p.59", or "¶27".
    public var pageLabel: String {
        var parts: [String] = []
        if let bookPage {
            let prefix = (pageConfidence == "low" && pageNumberSource == "estimated") ? "~" : ""
            parts.append("\(prefix)p.\(bookPage)")
        } else if paragraph == nil {
            parts.append("p.\(page)")
        }
        if let paragraph {
            parts.append("¶\(paragraph)")
        }
        return parts.joined(separator: " ")
    }
}
