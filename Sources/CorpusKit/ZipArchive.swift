//
//  ZipArchive.swift
//  CorpusKit
//
//  Cross-platform zip create/extract via ZIPFoundation, replacing the macOS-only
//  `Process` + `/usr/bin/ditto` (and `/usr/bin/unzip`) calls. Exposing it here — where
//  ZIPFoundation already lives — lets CorpusKit Studio's import/export pipeline run on iOS
//  as well as macOS without the app taking a direct ZIPFoundation dependency.
//

import Foundation
import ZIPFoundation

public enum ZipArchive {

    /// Create a zip archive of `source` (a file or directory) at `destination`.
    /// `keepParent: true` makes the source's own folder the top-level entry in the archive
    /// (matching `ditto --keepParent`).
    public static func zip(_ source: URL, to destination: URL, keepParent: Bool = true) throws {
        try FileManager.default.zipItem(
            at: source,
            to: destination,
            shouldKeepParent: keepParent,
            compressionMethod: .deflate
        )
    }

    /// Extract a zip archive into `destination` (which is created if needed).
    public static func unzip(_ archive: URL, to destination: URL) throws {
        try FileManager.default.unzipItem(at: archive, to: destination)
    }
}
