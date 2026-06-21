//
//  EmbeddingModelInfo.swift
//  CorpusKit
//
//  Single source of truth for the embedding model's identity and vector dimension.
//  Both the vector math (VectorStore/VectorIndex) and the embedder (EmbeddingService) derive
//  their dimension from `.current`, and exporters stamp `.current` into corpus metadata so a
//  later model swap can be detected at load (see the compatibility guard in WorkspaceManager).
//

import Foundation

public struct EmbeddingModelInfo: Sendable, Equatable, Codable {
    /// Stable model identifier, e.g. "Snowflake/snowflake-arctic-embed-m-v1.5".
    public let id: String
    /// Embedding vector dimension.
    public let dimension: Int
    /// Fixed token sequence length the model was traced at (tokenizer pads/truncates to this).
    public let seqLength: Int
    /// Bump when the bundled model changes in a way that invalidates existing embeddings.
    public let revision: Int

    public init(id: String, dimension: Int, seqLength: Int, revision: Int) {
        self.id = id
        self.dimension = dimension
        self.seqLength = seqLength
        self.revision = revision
    }

    /// The embedding model currently bundled with CorpusKit. Update this (and the bundled
    /// `.mlmodelc`) together whenever the model is swapped. The model self-pools (mean, with
    /// attention mask) and L2-normalizes internally — `EmbeddingService` reads its output directly.
    public static let current = EmbeddingModelInfo(
        id: "Snowflake/snowflake-arctic-embed-m-v1.5",
        dimension: 768,
        seqLength: 256,
        revision: 1
    )
}
