//
//  TokenStream.swift
//  WhisperBoard
//
//  Manages streaming token updates and transcription results to keyboard extension
//  Writes results to App Groups shared container
//

import Foundation

/// Handles streaming tokens and final transcription results to keyboard extension
class TokenStream {

    // MARK: - Properties

    private let streamQueue = DispatchQueue(label: "com.whisperboard.tokenstream", qos: .userInitiated)

    // MARK: - Initialization

    init() {
        // Initialize
    }

    // MARK: - Streaming Updates

    /// Send streaming token update to keyboard extension
    /// - Parameter tokenUpdate: Token update to send
    func sendTokenUpdate(_ tokenUpdate: TokenUpdate) {
        streamQueue.async {
            do {
                let updateData = try tokenUpdate.toJSONData()

                // Write to transcriptions directory with timestamp
                let fileName = "token_update_\(Int(Date().timeIntervalSince1970 * 1000)).json"

                try AppGroups.writeData(
                    updateData,
                    to: fileName,
                    in: AppGroups.Paths.transcriptions
                )

                print("[TokenStream] Sent token update: \"\(tokenUpdate.text)\"")

            } catch {
                print("[TokenStream] Failed to send token update: \(error)")
            }
        }
    }

    /// Send final transcription result to keyboard extension
    /// - Parameter result: Transcription result to send
    func sendTranscriptionResult(_ result: TranscriptionResult) {
        streamQueue.async {
            do {
                let resultData = try result.toJSONData()

                // Write to latest transcription file (overwrite)
                try AppGroups.writeData(
                    resultData,
                    to: AppGroups.Files.latestTranscription,
                    in: AppGroups.Paths.transcriptions
                )

                print("[TokenStream] Sent final transcription: \"\(result.text)\" (isFinal: \(result.isFinal))")

            } catch {
                print("[TokenStream] Failed to send transcription result: \(error)")
            }
        }
    }

    /// Send error message to keyboard extension
    /// - Parameter error: Error message to send
    func sendError(_ error: ErrorMessage) {
        streamQueue.async {
            do {
                let errorData = try error.toJSONData()

                // Write to error file
                try AppGroups.writeData(
                    errorData,
                    to: "error.json",
                    in: AppGroups.Paths.control
                )

                print("[TokenStream] Sent error: \(error.description)")

            } catch {
                print("[TokenStream] Failed to send error: \(error)")
            }
        }
    }

    // MARK: - Cleanup

    /// Clean up old transcription files (prevent accumulation)
    func cleanupOldFiles() {
        streamQueue.async {
            do {
                guard let transcriptionsPath = AppGroups.Paths.transcriptions else { return }

                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(
                    at: transcriptionsPath,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                // Delete files older than 5 minutes
                let cutoffTime = Date().addingTimeInterval(-300)

                for fileURL in files {
                    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                          let modDate = attributes[.modificationDate] as? Date else {
                        continue
                    }

                    if modDate < cutoffTime {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }

            } catch {
                print("[TokenStream] Failed to cleanup old files: \(error)")
            }
        }
    }

    /// Start periodic cleanup
    func startPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.cleanupOldFiles()
        }
    }
}
