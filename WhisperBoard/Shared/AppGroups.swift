//
//  AppGroups.swift
//  WhisperBoard
//
//  Manages App Groups shared container for IPC between keyboard extension and main app
//  Uses NSFileCoordinator for safe concurrent access to shared resources
//

import Foundation

/// App Groups configuration for secure IPC between keyboard extension and main app
enum AppGroups {

    /// The App Group identifier (configure in Xcode Capabilities and entitlements)
    static let identifier = "group.com.whisperboard.app"

    /// Shared container URL for App Groups
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Directory paths within the shared container
    enum Paths {
        /// Audio buffers directory for PCM chunks
        static var audioBuffers: URL? {
            containerURL?.appendingPathComponent("AudioBuffers", isDirectory: true)
        }

        /// Transcription results directory
        static var transcriptions: URL? {
            containerURL?.appendingPathComponent("Transcriptions", isDirectory: true)
        }

        /// Control signals directory
        static var control: URL? {
            containerURL?.appendingPathComponent("Control", isDirectory: true)
        }

        /// Settings and configuration
        static var settings: URL? {
            containerURL?.appendingPathComponent("Settings", isDirectory: true)
        }
    }

    /// File names for specific communication channels
    enum Files {
        /// Current audio chunk being processed
        static let currentAudioChunk = "current_audio.pcm"

        /// Latest transcription result
        static let latestTranscription = "latest_transcription.json"

        /// Control signal file (START, STOP, CANCEL)
        static let controlSignal = "control_signal.json"

        /// Shared settings
        static let sharedSettings = "settings.json"

        /// Status file for app state
        static let statusFile = "status.json"
    }

    /// Initialize shared container directories
    static func initializeSharedContainer() throws {
        guard let containerURL = containerURL else {
            throw AppGroupsError.containerNotFound
        }

        let fileManager = FileManager.default
        let directories = [
            Paths.audioBuffers,
            Paths.transcriptions,
            Paths.control,
            Paths.settings
        ]

        for directory in directories.compactMap({ $0 }) {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        }

        print("[AppGroups] Initialized shared container at: \(containerURL.path)")
    }

    /// Write data to shared container using NSFileCoordinator for safety
    static func writeData(_ data: Data, to fileName: String, in directory: URL?) throws {
        guard let directory = directory else {
            throw AppGroupsError.invalidDirectory
        }

        let fileURL = directory.appendingPathComponent(fileName)
        let coordinator = NSFileCoordinator()
        var writeError: Error?

        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: nil) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = writeError {
            throw error
        }
    }

    /// Read data from shared container using NSFileCoordinator for safety
    static func readData(from fileName: String, in directory: URL?) throws -> Data {
        guard let directory = directory else {
            throw AppGroupsError.invalidDirectory
        }

        let fileURL = directory.appendingPathComponent(fileName)
        let coordinator = NSFileCoordinator()
        var readData: Data?
        var readError: Error?

        coordinator.coordinate(readingItemAt: fileURL, options: [], error: nil) { url in
            do {
                readData = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }

        if let error = readError {
            throw error
        }

        guard let data = readData else {
            throw AppGroupsError.readFailed
        }

        return data
    }

    /// Delete file from shared container
    static func deleteFile(_ fileName: String, in directory: URL?) throws {
        guard let directory = directory else {
            throw AppGroupsError.invalidDirectory
        }

        let fileURL = directory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Check if file exists in shared container
    static func fileExists(_ fileName: String, in directory: URL?) -> Bool {
        guard let directory = directory else {
            return false
        }

        let fileURL = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get file modification date
    static func fileModificationDate(_ fileName: String, in directory: URL?) -> Date? {
        guard let directory = directory else {
            return nil
        }

        let fileURL = directory.appendingPathComponent(fileName)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return modDate
    }
}

/// Errors that can occur during App Groups operations
enum AppGroupsError: LocalizedError {
    case containerNotFound
    case invalidDirectory
    case writeFailed
    case readFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "App Groups shared container not found. Check entitlements and provisioning."
        case .invalidDirectory:
            return "Invalid directory path in App Groups container."
        case .writeFailed:
            return "Failed to write data to App Groups container."
        case .readFailed:
            return "Failed to read data from App Groups container."
        case .fileNotFound:
            return "Requested file not found in App Groups container."
        }
    }
}
