//
//  CorpusMetadata.swift
//  CorpusKit
//
//  Portable corpus metadata (corpus_meta.json). Moved into the package (Phase 4a/Phase C) so the
//  authoring app (CorpusKit Studio), the reader, and BigBookViaLLM all share one definition and
//  one schema. Preserves the AD-20 schema: canonical `bundle_schema_version`, with backward-compat
//  reading of the legacy `bundle_format_version` (normalized to schema 1, never written back).
//

import Foundation

/// Metadata stored in `corpus_meta.json`.
public struct CorpusMetadata: Codable {
    public let bundleSchemaVersion: Int
    public let id: UUID
    public var title: String
    public let sourceFileName: String  // Original PDF filename
    public let sourceType: String      // "pdf", "epub"
    public var corpusVersion: Int      // User-controlled content version
    public let createdAt: Date
    public var updatedAt: Date

    // Chunking configuration
    public var chunkSize: Int
    public var chunkOverlap: Int
    public var chunkMinWordCount: Int
    public var contentStartPage: Int
    public var dotPageThreshold: Float
    public var wordsPerPage: Int  // For EPUB page estimation (default 280)

    // Authority configuration
    public var authorityWeight: Float
    public var authorityRank: Int
    public var authorityNote: String

    // Processing flags
    public var isEmbedded: Bool
    public var isExported: Bool
    public var lastExportDate: Date?
    public var serverVersion: Int?

    // Corpus type
    public var corpusType: String  // "generic", "bigBook1939", etc.

    // MARK: Export-bundle presentation fields
    // Populated only when this metadata is written into an exported .corpus bundle.
    // Absent (nil, and omitted from JSON) for working-directory corpus_meta.json files.
    public var source: String?            // Human-facing source label from the export config
    public var copyright: String?
    public var licenseType: String?       // Raw value of CorpusExporter.ExportConfig.LicenseType
    public var curator: String?
    public var embeddingModel: String?    // e.g. "Snowflake/snowflake-arctic-embed-m-v1.5"
    public var embeddingDimension: Int?   // e.g. 768
    public var chunkCount: Int?           // Number of chunks in the exported bundle
    public var exportedAt: Date?          // Timestamp the bundle was written

    enum CodingKeys: String, CodingKey {
        case bundleSchemaVersion = "bundle_schema_version"
        case id
        case title
        case sourceFileName = "source_file_name"
        case sourceType = "source_type"
        case corpusVersion = "corpus_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case chunkSize = "chunk_size"
        case chunkOverlap = "chunk_overlap"
        case chunkMinWordCount = "chunk_min_word_count"
        case contentStartPage = "content_start_page"
        case dotPageThreshold = "dot_page_threshold"
        case wordsPerPage = "words_per_page"
        case authorityWeight = "authority_weight"
        case authorityRank = "authority_rank"
        case authorityNote = "authority_note"
        case isEmbedded = "is_embedded"
        case isExported = "is_exported"
        case lastExportDate = "last_export_date"
        case serverVersion = "server_version"
        case corpusType = "corpus_type"
        case source
        case copyright
        case licenseType = "license_type"
        case curator
        case embeddingModel = "embedding_model"
        case embeddingDimension = "embedding_dimension"
        case chunkCount = "chunk_count"
        case exportedAt = "exported_at"
    }

    /// Legacy keys read for migration only — never written back out (see AD-20).
    private enum LegacyCodingKeys: String, CodingKey {
        case bundleFormatVersion = "bundle_format_version"
    }

    public init(
        id: UUID = UUID(),
        title: String,
        sourceFileName: String,
        sourceType: String = "pdf",
        corpusVersion: Int = 3,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        chunkSize: Int = 200,
        chunkOverlap: Int = 50,
        chunkMinWordCount: Int = 40,
        contentStartPage: Int = 1,
        dotPageThreshold: Float = 0.2,
        wordsPerPage: Int = 280,
        authorityWeight: Float = 1.0,
        authorityRank: Int = 3,
        authorityNote: String = "",
        isEmbedded: Bool = false,
        isExported: Bool = false,
        lastExportDate: Date? = nil,
        serverVersion: Int? = nil,
        corpusType: String = "generic",
        source: String? = nil,
        copyright: String? = nil,
        licenseType: String? = nil,
        curator: String? = nil,
        embeddingModel: String? = nil,
        embeddingDimension: Int? = nil,
        chunkCount: Int? = nil,
        exportedAt: Date? = nil
    ) {
        self.bundleSchemaVersion = 1  // Current schema version
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.sourceType = sourceType
        self.corpusVersion = corpusVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.chunkMinWordCount = chunkMinWordCount
        self.contentStartPage = contentStartPage
        self.dotPageThreshold = dotPageThreshold
        self.wordsPerPage = wordsPerPage
        self.authorityWeight = authorityWeight
        self.authorityRank = authorityRank
        self.authorityNote = authorityNote
        self.isEmbedded = isEmbedded
        self.isExported = isExported
        self.lastExportDate = lastExportDate
        self.serverVersion = serverVersion
        self.corpusType = corpusType
        self.source = source
        self.copyright = copyright
        self.licenseType = licenseType
        self.curator = curator
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.chunkCount = chunkCount
        self.exportedAt = exportedAt
    }

    // Custom decoder for backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Schema version migration (AD-20): accept the canonical `bundle_schema_version`, and
        // tolerate the legacy `bundle_format_version` that older export bundles wrote. The legacy
        // key lived in a *different* namespace (export-bundle format, where the value was 2 — not
        // the working-dir schema, where it was 1), so a legacy-keyed file is normalized to the
        // current schema version rather than copying its number across. Only `bundle_schema_version`
        // is ever written back out.
        if let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .bundleSchemaVersion) {
            bundleSchemaVersion = schemaVersion
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            if (try? legacy.decodeIfPresent(Int.self, forKey: .bundleFormatVersion)) != nil {
                dlog("ℹ️ CorpusMetadata: migrating legacy bundle_format_version → bundle_schema_version=1")
            }
            bundleSchemaVersion = 1
        }
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        corpusVersion = try container.decode(Int.self, forKey: .corpusVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        chunkSize = try container.decode(Int.self, forKey: .chunkSize)
        chunkOverlap = try container.decode(Int.self, forKey: .chunkOverlap)
        chunkMinWordCount = try container.decode(Int.self, forKey: .chunkMinWordCount)
        contentStartPage = try container.decode(Int.self, forKey: .contentStartPage)
        dotPageThreshold = try container.decode(Float.self, forKey: .dotPageThreshold)

        // Backward compatibility: wordsPerPage defaults to 280 if missing
        wordsPerPage = try container.decodeIfPresent(Int.self, forKey: .wordsPerPage) ?? 280

        authorityWeight = try container.decode(Float.self, forKey: .authorityWeight)
        authorityRank = try container.decode(Int.self, forKey: .authorityRank)
        authorityNote = try container.decode(String.self, forKey: .authorityNote)
        isEmbedded = try container.decode(Bool.self, forKey: .isEmbedded)
        isExported = try container.decode(Bool.self, forKey: .isExported)
        lastExportDate = try container.decodeIfPresent(Date.self, forKey: .lastExportDate)
        serverVersion = try container.decodeIfPresent(Int.self, forKey: .serverVersion)
        corpusType = try container.decode(String.self, forKey: .corpusType)

        // Export-bundle presentation fields (absent in working-directory metadata)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
        licenseType = try container.decodeIfPresent(String.self, forKey: .licenseType)
        curator = try container.decodeIfPresent(String.self, forKey: .curator)
        embeddingModel = try container.decodeIfPresent(String.self, forKey: .embeddingModel)
        embeddingDimension = try container.decodeIfPresent(Int.self, forKey: .embeddingDimension)
        chunkCount = try container.decodeIfPresent(Int.self, forKey: .chunkCount)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt)
    }
}
