import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum SnapshotExportFileError: Error, Equatable {
    case generateFailed
    case writeFailed
    case replaceFailed
}

protocol SnapshotExportFileIO {
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at destination: URL, withItemAt temp: URL) throws
    func removeItem(at url: URL) throws
}

/// Writes a finished HTML payload via a temp file in the destination directory, then replaces.
enum SnapshotExportFile {
    static func commit(html: String, to destination: URL) throws {
        try commit(data: Data(html.utf8), to: destination)
    }

    static func commit(data: Data?, to destination: URL) throws {
        try commit(data: data, to: destination, io: LiveSnapshotExportFileIO())
    }

    static func commit(data: Data?, to destination: URL, io: any SnapshotExportFileIO) throws {
        guard let data else {
            throw SnapshotExportFileError.generateFailed
        }
        let temp = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".pulse-snapshot-\(UUID().uuidString).tmp")
        do {
            try io.write(data, to: temp)
        } catch {
            try? io.removeItem(at: temp)
            throw SnapshotExportFileError.writeFailed
        }
        do {
            try io.replaceItem(at: destination, withItemAt: temp)
        } catch {
            try? io.removeItem(at: temp)
            throw SnapshotExportFileError.replaceFailed
        }
        try? io.removeItem(at: temp)
    }
}

struct LiveSnapshotExportFileIO: SnapshotExportFileIO {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    /// `FileManager.replaceItemAt` on swift-corelibs reports the destination missing
    /// and can drop its bytes. `rename` in the same directory replaces atomically.
    func replaceItem(at destination: URL, withItemAt temp: URL) throws {
        let code = temp.withUnsafeFileSystemRepresentation { tempPath -> Int32 in
            destination.withUnsafeFileSystemRepresentation { destPath -> Int32 in
                guard let tempPath, let destPath else { return -1 }
                #if canImport(Darwin)
                return Darwin.rename(tempPath, destPath)
                #elseif canImport(Glibc)
                return Glibc.rename(tempPath, destPath)
                #else
                return -1
                #endif
            }
        }
        guard code == 0 else {
            throw SnapshotExportFileError.replaceFailed
        }
    }

    func removeItem(at url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        try manager.removeItem(at: url)
    }
}
