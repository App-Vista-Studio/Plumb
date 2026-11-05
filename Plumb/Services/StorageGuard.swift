//
//  StorageGuard.swift
//  Plumb
//
//  Keeps the app working when the device is out of storage. When a write fails because the disk is
//  full, Plumb clears everything it can regenerate (caches, temporary files, URL cache) and retries
//  once. Saved projects and measurements live in Application Support and are never touched here.
//

import Foundation

nonisolated enum StorageGuard {
    /// Below this much free space a write is treated as at risk and caches are cleared first.
    static let lowSpaceBytes: Int64 = 50 * 1_048_576

    /// True for "no space left on device" in any of the shapes Foundation reports it.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) || ns.code == Int(EDQUOT) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }

    /// Free bytes the app may use, or nil when the system does not say.
    static var availableBytes: Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static var isLowOnSpace: Bool { availableBytes.map { $0 < lowSpaceBytes } ?? false }

    /// The app's own regenerable storage: its temporary and caches directories (inside the app sandbox on iOS).
    static var appCacheRoots: [URL] {
        let fm = FileManager.default
        var roots = [fm.temporaryDirectory]
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { roots.append(caches) }
        return roots
    }

    /// Deletes the contents of `roots` (default: the app's caches and temporary files). Returns the number of bytes freed (best effort).
    @discardableResult
    static func clearCaches(keeping keep: Set<URL> = [], in roots: [URL] = appCacheRoots) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        let keepPaths = Set(keep.map { $0.standardizedFileURL.path })
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for item in items where !keepPaths.contains(item.standardizedFileURL.path) {
                freed += size(of: item)
                try? fm.removeItem(at: item)
            }
        }
        if roots == appCacheRoots { URLCache.shared.removeAllCachedResponses() }
        return freed
    }

    /// Writes `data`. If the disk is full (or nearly), clears caches and retries once.
    @discardableResult
    static func write(_ data: Data, to url: URL, options: Data.WritingOptions = [.atomic]) -> Bool {
        if isLowOnSpace { clearCaches(keeping: [url]) }
        do {
            try data.write(to: url, options: options)
            return true
        } catch {
            guard isOutOfSpace(error) else { return false }
            clearCaches(keeping: [url])
            return (try? data.write(to: url, options: options)) != nil
        }
    }

    /// Runs `operation`; if it fails while the disk is low, clears caches and runs it once more.
    static func retrying<T>(_ operation: () -> T?) -> T? {
        if isLowOnSpace { clearCaches() }
        if let result = operation() { return result }
        guard isLowOnSpace else { return nil }
        clearCaches()
        return operation()
    }

    /// Removes temporary files left by earlier launches. Call once at launch.
    static func trimOnLaunch() {
        if isLowOnSpace { clearCaches() }
    }

    private static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }
}
