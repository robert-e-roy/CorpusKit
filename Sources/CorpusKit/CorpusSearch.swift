//
//  CorpusSearch.swift
//  CorpusKit
//
//  One-stop retrieval over a LoadedCorpus: embeds the query with the bundled model, runs the
//  importance-weighted VectorIndex search, and optionally sentence-ranks the top hit. Enforces the
//  embedding-model compatibility guard (a corpus embedded with a different dimension can't be
//  searched with the current model). Shared by the reader, BigBook, and any future consumer.
//

import Foundation

public struct CorpusSearchResult {
    public let chunk: Chunk
    public let rawScore: Float        // cosine similarity
    public let finalScore: Float      // cosine × chunk importance weight
    public var winningSentence: String?   // populated when sentence ranking is requested
    public var sentenceScore: Float?

    public init(chunk: Chunk, rawScore: Float, finalScore: Float,
                winningSentence: String? = nil, sentenceScore: Float? = nil) {
        self.chunk = chunk
        self.rawScore = rawScore
        self.finalScore = finalScore
        self.winningSentence = winningSentence
        self.sentenceScore = sentenceScore
    }
}

public final class CorpusSearch {

    public enum SearchError: Error, LocalizedError {
        case incompatibleModel(expected: String, found: String)
        public var errorDescription: String? {
            switch self {
            case .incompatibleModel(let expected, let found):
                return "This corpus was embedded with \(found), but the app uses \(expected). Re-embed the corpus with the current model."
            }
        }
    }

    public let metadata: CorpusMetadata
    private let index: VectorIndex
    private let embedder: EmbeddingService

    /// Build over a loaded corpus. Throws `incompatibleModel` if the corpus's embedding dimension
    /// doesn't match the current model (hard incompatibility). A differing model id at the same
    /// dimension is allowed but logged.
    public init(corpus: LoadedCorpus, embedder: EmbeddingService = EmbeddingService()) throws {
        if let dim = corpus.metadata.embeddingDimension, dim != EmbeddingModelInfo.current.dimension {
            throw SearchError.incompatibleModel(
                expected: "\(EmbeddingModelInfo.current.id) (\(EmbeddingModelInfo.current.dimension)-dim)",
                found: "\(corpus.metadata.embeddingModel ?? "unknown") (\(dim)-dim)"
            )
        }
        if let model = corpus.metadata.embeddingModel, model != EmbeddingModelInfo.current.id {
            print("⚠️ CorpusSearch: corpus embedded with '\(model)' but current model is '\(EmbeddingModelInfo.current.id)' — similarity semantics may differ.")
        }
        self.metadata = corpus.metadata
        self.embedder = embedder
        self.index = VectorIndex()
        index.build(chunks: corpus.chunks)
    }

    public var isModelLoaded: Bool { embedder.isLoaded }

    /// Load the embedding model (idempotent). Safe to call before the first search to control timing.
    public func loadModel() async throws {
        if !embedder.isLoaded { try await embedder.load() }
    }

    /// Embed the query (the user's question — matching the production retrieval path) and return
    /// the top-k importance-weighted results. When `rankSentences` is true, the top hit's most
    /// relevant sentence is attached.
    public func search(_ query: String, k: Int = 3, rankSentences: Bool = false) async throws -> [CorpusSearchResult] {
        if !embedder.isLoaded { try await embedder.load() }
        let queryEmbedding = try await embedder.embed(query)
        let hits = index.search(query: queryEmbedding, k: k)

        var results = hits.map {
            CorpusSearchResult(chunk: $0.chunk, rawScore: $0.rawScore, finalScore: $0.finalScore)
        }

        if rankSentences, let top = hits.first {
            let scoped = [ScoredChunk(item: top.chunk, rawScore: top.finalScore, weightedScore: top.finalScore)]
            let ranked = try await SentenceRanker().rank(query: queryEmbedding, chunks: scoped, embeddingService: embedder)
            if let best = ranked.first, let i = results.firstIndex(where: { $0.chunk.id == best.chunkID }) {
                results[i].winningSentence = best.text
                results[i].sentenceScore = best.score
            }
        }
        return results
    }
}
