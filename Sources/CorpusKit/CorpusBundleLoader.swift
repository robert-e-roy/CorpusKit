//
//  CorpusBundleLoader.swift
//  CorpusKit
//
//  Loads a corpus for consumption (reader / BigBook): decodes corpus_meta.json + chunks.json and
//  parses embeddings.npy, merging the embeddings back onto the chunks so a VectorIndex can be built
//  directly. Supports loading from an extracted `.corpus` directory (cross-platform) or, on macOS,
//  from a `.corpus.zip` (extracted with ZIPFoundation — cross-platform). Includes an iCloud
//  "ensure downloaded" helper.
//

import Foundation
import ZIPFoundation

/// A corpus loaded and ready for retrieval.
public struct LoadedCorpus {
    public let metadata: CorpusMetadata
    /// Chunks with their embeddings populated (merged from embeddings.npy).
    public let chunks: [Chunk]
    /// The extracted `.corpus` directory (for accessing other files, e.g. chapter_config.json).
    public let directory: URL

    public init(metadata: CorpusMetadata, chunks: [Chunk], directory: URL) {
        self.metadata = metadata
        self.chunks = chunks
        self.directory = directory
    }
}

public enum CorpusBundleError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidBundle(String)
    case npyParseError(String)
    case countMismatch(chunks: Int, embeddings: Int)
    case extractionFailed(String)
    case iCloudDownloadTimeout(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let n): return "Corpus file not found: \(n)"
        case .invalidBundle(let m): return "Invalid corpus bundle: \(m)"
        case .npyParseError(let m): return "Could not parse embeddings.npy: \(m)"
        case .countMismatch(let c, let e): return "Chunk/embedding count mismatch: \(c) chunks vs \(e) embeddings"
        case .extractionFailed(let m): return "Failed to extract .corpus.zip: \(m)"
        case .iCloudDownloadTimeout(let u): return "Timed out downloading iCloud item: \(u.lastPathComponent)"
        }
    }
}

public final class CorpusBundleLoader {

    public init() {}

    /// Load from an extracted `.corpus` directory (cross-platform).
    public func load(corpusDirectory dir: URL) throws -> LoadedCorpus {
        let metaURL = dir.appendingPathComponent("corpus_meta.json")
        let chunksURL = dir.appendingPathComponent("chunks.json")
        let npyURL = dir.appendingPathComponent("embeddings.npy")

        guard FileManager.default.fileExists(atPath: metaURL.path) else { throw CorpusBundleError.fileNotFound("corpus_meta.json") }
        guard FileManager.default.fileExists(atPath: chunksURL.path) else { throw CorpusBundleError.fileNotFound("chunks.json") }
        guard FileManager.default.fileExists(atPath: npyURL.path) else { throw CorpusBundleError.fileNotFound("embeddings.npy") }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(CorpusMetadata.self, from: Data(contentsOf: metaURL))

        // chunks.json carries chunk text/metadata; embeddings live in embeddings.npy.
        var chunks = try JSONDecoder().decode([Chunk].self, from: Data(contentsOf: chunksURL))
        let embeddings = try Self.parseNpyFloat32(Data(contentsOf: npyURL))

        guard chunks.count == embeddings.count else {
            throw CorpusBundleError.countMismatch(chunks: chunks.count, embeddings: embeddings.count)
        }
        // Merge embeddings onto chunks so VectorIndex.build(chunks:) works directly.
        for i in chunks.indices { chunks[i].embedding = embeddings[i] }

        return LoadedCorpus(metadata: metadata, chunks: chunks, directory: dir)
    }

    /// Load from a `.corpus.zip` by extracting with ZIPFoundation (cross-platform: iOS + macOS).
    public func load(corpusZip zipURL: URL) throws -> LoadedCorpus {
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.unzipItem(at: zipURL, to: extractDir)
        } catch {
            throw CorpusBundleError.extractionFailed(error.localizedDescription)
        }

        // The bundle contains an inner `<Title>.corpus` directory.
        let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        guard let corpusDir = contents.first(where: { $0.pathExtension == "corpus" }) else {
            throw CorpusBundleError.invalidBundle("no .corpus directory inside the zip")
        }
        return try load(corpusDirectory: corpusDir)
    }

    /// Ensure an iCloud (ubiquitous) item is downloaded locally before loading. No-op for local
    /// files. Polls the downloading status (always use file coordination for the subsequent read).
    public func ensureDownloaded(_ url: URL, timeout: TimeInterval = 60) throws {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return }   // local file — nothing to do
        if values?.ubiquitousItemDownloadingStatus == .current { return }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            if status == .current { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw CorpusBundleError.iCloudDownloadTimeout(url)
    }

    // MARK: - NumPy .npy parsing (v1/v2, float32, C-order)

    /// Parse a `.npy` file of little-endian float32 (`<f4`), C-order, shape `(rows, cols)`.
    static func parseNpyFloat32(_ data: Data) throws -> [[Float]] {
        let b = [UInt8](data)
        guard b.count > 10,
              b[0] == 0x93, b[1] == 0x4E, b[2] == 0x55, b[3] == 0x4D, b[4] == 0x50, b[5] == 0x59
        else { throw CorpusBundleError.npyParseError("bad magic") }

        let major = b[6]
        let headerLenSize = major >= 2 ? 4 : 2
        guard b.count >= 8 + headerLenSize else { throw CorpusBundleError.npyParseError("truncated header length") }
        var headerLen = 0
        for i in 0..<headerLenSize { headerLen |= Int(b[8 + i]) << (8 * i) }

        let headerStart = 8 + headerLenSize
        guard b.count >= headerStart + headerLen else { throw CorpusBundleError.npyParseError("truncated header") }
        guard let header = String(bytes: b[headerStart..<(headerStart + headerLen)], encoding: .ascii) else {
            throw CorpusBundleError.npyParseError("non-ascii header")
        }
        guard header.contains("'<f4'") else { throw CorpusBundleError.npyParseError("expected little-endian float32 (<f4)") }
        guard header.contains("'fortran_order': False") else { throw CorpusBundleError.npyParseError("expected C-order") }

        // shape: ( rows , cols )
        guard let shapeKey = header.range(of: "'shape':") else { throw CorpusBundleError.npyParseError("no shape") }
        let tail = header[shapeKey.upperBound...]
        guard let open = tail.firstIndex(of: "("), let close = tail.firstIndex(of: ")") else {
            throw CorpusBundleError.npyParseError("malformed shape")
        }
        let dims = tail[tail.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard dims.count == 2 else { throw CorpusBundleError.npyParseError("expected 2-D shape, got \(dims)") }
        let rows = dims[0], cols = dims[1]

        let floatStart = headerStart + headerLen
        let needed = rows * cols * 4
        guard b.count - floatStart >= needed else { throw CorpusBundleError.npyParseError("data shorter than shape") }

        var result = [[Float]]()
        result.reserveCapacity(rows)
        for r in 0..<rows {
            var row = [Float](repeating: 0, count: cols)
            let rowBase = floatStart + r * cols * 4
            for c in 0..<cols {
                let o = rowBase + c * 4
                let bits = UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
                row[c] = Float(bitPattern: bits)
            }
            result.append(row)
        }
        return result
    }
}
