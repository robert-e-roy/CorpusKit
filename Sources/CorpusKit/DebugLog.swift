//
//  DebugLog.swift
//  CorpusKit
//
//  Gated verbose console tracing for the engine. CorpusKit historically used emoji-prefixed
//  `print()` diagnostics (🧠 ✅ …) — handy while developing the retrieval/embedding path but
//  far too noisy for the host apps' day-to-day console. Every `print(` was routed through
//  `dlog(`, which is a no-op unless verbose logging is explicitly enabled, so the traces stay
//  in source but the console is quiet by default for every consumer (Studio, Reader, …).
//
//  Re-enable (per host app) by any of:
//    • flip `CKDebugLog.forceEnabled` to `true` (quickest), or
//    • set the `CKVerboseLogging` user default in the host app
//      (`defaults write <host.bundle.id> CKVerboseLogging -bool YES`, or a launch arg in DEBUG).
//

import Foundation

enum CKDebugLog {
    /// Hard override — set to `true` to restore verbose engine tracing everywhere.
    static let forceEnabled = false

    /// Resolved once. Off by default; reads the host app's `CKVerboseLogging` default in DEBUG.
    static let isEnabled: Bool = {
        if forceEnabled { return true }
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "CKVerboseLogging")
        #else
        return false
        #endif
    }()
}

/// Drop-in replacement for `print(…)` that only emits when verbose engine logging is enabled.
@inline(__always)
func dlog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    guard CKDebugLog.isEnabled else { return }
    Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
}
