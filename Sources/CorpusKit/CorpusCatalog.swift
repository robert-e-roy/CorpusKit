//
//  CorpusCatalog.swift
//  CorpusKit
//
//  Enumerates available corpora across sources (bundled / local / iCloud / user-picked folder) for
//  a "list and select" UI. Returns lightweight descriptors without loading embeddings: for an
//  extracted `.corpus` directory it reads corpus_meta.json directly; for a `.corpus.zip` it derives
//  the title/version from the filename (full metadata + the embedding-model compatibility check
//  happen at load time via CorpusBundleLoader / CorpusSearch).
//

import Foundation

public struct CorpusDescriptor: Identifiable, Hashable {
    public enum Source: String, Sendable, Hashable {
        case bundled, local, iCloud, userFolder
    }

    /// Stable identity (standardized file path).
    public let id: String
    public let title: String
    public let version: Int?
    public let source: Source
    /// The `.corpus.zip` file or extracted `.corpus` directory.
    public let url: URL
    /// Present only when read from an extracted `.corpus` directory (cheap); nil for `.zip`.
    public let embeddingModel: String?
    public let embeddingDimension: Int?
    /// nil = unknown (zip, not yet loaded); true/false once dimension is known.
    public let isCompatible: Bool?

    public init(id: String, title: String, version: Int?, source: Source, url: URL,
                embeddingModel: String? = nil, embeddingDimension: Int? = nil, isCompatible: Bool? = nil) {
        self.id = id
        self.title = title
        self.version = version
        self.source = source
        self.url = url
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.isCompatible = isCompatible
    }
}

public final class CorpusCatalog {

    public init() {}

    /// Enumerate corpora across several labeled source directories, de-duplicated by resolved path.
    public func descriptors(sources: [(directory: URL, source: CorpusDescriptor.Source)]) -> [CorpusDescriptor] {
        var seen = Set<String>()
        var out: [CorpusDescriptor] = []
        for s in sources {
            for d in descriptors(in: s.directory, source: s.source) where !seen.contains(d.id) {
                seen.insert(d.id)
                out.append(d)
            }
        }
        return out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Enumerate corpora in a single directory: `*.corpus.zip` files and extracted `*.corpus` dirs.
    public func descriptors(in directory: URL, source: CorpusDescriptor.Source) -> [CorpusDescriptor] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var result: [CorpusDescriptor] = []
        for url in entries {
            let name = url.lastPathComponent
            if name.hasSuffix(".corpus.zip") {
                let (title, version) = Self.titleAndVersion(fromFileName: String(name.dropLast(".corpus.zip".count)))
                result.append(CorpusDescriptor(
                    id: url.standardizedFileURL.path, title: title, version: version,
                    source: source, url: url
                ))
            } else if url.pathExtension == "corpus",
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                result.append(descriptorForCorpusDirectory(url, source: source))
            }
        }
        return result
    }

    // MARK: - Helpers

    private func descriptorForCorpusDirectory(_ dir: URL, source: CorpusDescriptor.Source) -> CorpusDescriptor {
        let metaURL = dir.appendingPathComponent("corpus_meta.json")
        let (fallbackTitle, fallbackVersion) = Self.titleAndVersion(fromFileName: String(dir.lastPathComponent.dropLast(".corpus".count)))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? decoder.decode(CorpusMetadata.self, from: data) {
            let compatible = meta.embeddingDimension.map { $0 == EmbeddingModelInfo.current.dimension }
            return CorpusDescriptor(
                id: dir.standardizedFileURL.path, title: meta.title, version: meta.corpusVersion,
                source: source, url: dir, embeddingModel: meta.embeddingModel,
                embeddingDimension: meta.embeddingDimension, isCompatible: compatible
            )
        }
        return CorpusDescriptor(
            id: dir.standardizedFileURL.path, title: fallbackTitle, version: fallbackVersion,
            source: source, url: dir
        )
    }

    /// Parse the export convention `<Title>_v<N>` → (title, version). Falls back to the whole name.
    static func titleAndVersion(fromFileName base: String) -> (title: String, version: Int?) {
        if let r = base.range(of: "_v[0-9]+$", options: .regularExpression) {
            let title = String(base[base.startIndex..<r.lowerBound])
            let version = Int(base[base.index(r.lowerBound, offsetBy: 2)..<r.upperBound])
            return (title.isEmpty ? base : title, version)
        }
        return (base, nil)
    }
}
