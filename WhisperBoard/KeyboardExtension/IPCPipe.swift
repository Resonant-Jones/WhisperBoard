//
//  IPCPipe.swift
//  WhisperBoard Keyboard Extension
//
//  Handles IPC communication between keyboard extension and main app
//  Uses App Groups shared container for data exchange
//

import Foundation

/// IPC communication pipe between keyboard extension and main app
class IPCPipe {

    // MARK: - Properties

    private let ipcQueue = DispatchQueue(label: "com.whisperboard.ipc", qos: .userInitiated)
    private var monitorTimer: Timer?
    private let pollingInterval: TimeInterval = 0.1  // 100ms for responsive updates
    private var lastTranscriptionCheck: Date?

    /// Callbacks
    var onTranscriptionUpdate: ((TranscriptionResult) -> Void)?
    var onTokenUpdate: ((TokenUpdate) -> Void)?
    var onError: ((ErrorMessage) -> Void)?

    // MARK: - Sending Messages

    /// Send control signal to main app
    /// - Parameters:
    ///   - signal: Control signal type
    ///   - sessionId: Session identifier
    func sendControlSignal(_ signal: ControlSignal, sessionId: String) {
        ipcQueue.async {
            do {
                let controlMsg = ControlMessage(signal: signal, sessionId: sessionId)
                let msgData = try controlMsg.toJSONData()

                try AppGroups.writeData(
                    msgData,
                    to: AppGroups.Files.controlSignal,
                    in: AppGroups.Paths.control
                )

                print("[IPCPipe] Sent control signal: \(signal)")

            } catch {
                print("[IPCPipe] Failed to send control signal: \(error)")
            }
        }
    }

    /// Send audio chunk to main app
    /// - Parameters:
    ///   - audioData: PCM audio data
    ///   - metadata: Audio chunk metadata
    func sendAudioChunk(_ audioData: Data, metadata: AudioChunkMetadata) throws {
        // Generate unique filename for this chunk
        let pcmFileName = "chunk_\(metadata.sessionId)_\(metadata.chunkId).pcm"

        // Write PCM data
        try AppGroups.writeData(
            audioData,
            to: pcmFileName,
            in: AppGroups.Paths.audioBuffers
        )

        // Write metadata
        let chunkMsg = AudioChunkMessage(metadata: metadata, pcmFileName: pcmFileName)
        let metadataData = try chunkMsg.toJSONData()
        let metadataFileName = "chunk_\(metadata.sessionId)_\(metadata.chunkId).json"

        try AppGroups.writeData(
            metadataData,
            to: metadataFileName,
            in: AppGroups.Paths.audioBuffers
        )

        print("[IPCPipe] Sent audio chunk \(metadata.chunkId)")
    }

    // MARK: - Receiving Messages

    /// Start monitoring for transcription updates from main app
    func startMonitoring() {
        stopMonitoring()

        print("[IPCPipe] Started monitoring for transcription updates")

        monitorTimer = Timer.scheduledTimer(
            withTimeInterval: pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkForTranscriptionUpdates()
            self?.checkForErrors()
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Check for new transcription results
    private func checkForTranscriptionUpdates() {
        ipcQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Check latest transcription file
                if AppGroups.fileExists(AppGroups.Files.latestTranscription, in: AppGroups.Paths.transcriptions) {
                    // Check modification date to avoid processing same result multiple times
                    let modDate = AppGroups.fileModificationDate(
                        AppGroups.Files.latestTranscription,
                        in: AppGroups.Paths.transcriptions
                    )

                    if let modDate = modDate,
                       let lastCheck = self.lastTranscriptionCheck,
                       modDate <= lastCheck {
                        // Already processed this result
                        return
                    }

                    // Read transcription result
                    let data = try AppGroups.readData(
                        from: AppGroups.Files.latestTranscription,
                        in: AppGroups.Paths.transcriptions
                    )

                    let result = try data.decode(as: TranscriptionResult.self)

                    // Update last check time
                    self.lastTranscriptionCheck = Date()

                    // Notify callback on main thread
                    DispatchQueue.main.async {
                        self.onTranscriptionUpdate?(result)
                    }
                }

                // Also check for streaming token updates
                self.checkForTokenUpdates()

            } catch {
                // Silently ignore errors (file might not exist yet)
            }
        }
    }

    /// Check for streaming token updates
    private func checkForTokenUpdates() {
        do {
            guard let transcriptionsPath = AppGroups.Paths.transcriptions else { return }

            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(
                at: transcriptionsPath,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Find token update files
            let tokenUpdateFiles = files
                .filter { $0.lastPathComponent.starts(with: "token_update_") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return date1 < date2
                }

            // Process and delete token update files
            for fileURL in tokenUpdateFiles {
                let data = try Data(contentsOf: fileURL)
                let tokenUpdate = try data.decode(as: TokenUpdate.self)

                // Notify callback on main thread
                DispatchQueue.main.async {
                    self.onTokenUpdate?(tokenUpdate)
                }

                // Delete processed file
                try fileManager.removeItem(at: fileURL)
            }

        } catch {
            // Silently ignore errors
        }
    }

    /// Check for error messages
    private func checkForErrors() {
        ipcQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                if AppGroups.fileExists("error.json", in: AppGroups.Paths.control) {
                    let data = try AppGroups.readData(
                        from: "error.json",
                        in: AppGroups.Paths.control
                    )

                    let errorMsg = try data.decode(as: ErrorMessage.self)

                    // Notify callback on main thread
                    DispatchQueue.main.async {
                        self.onError?(errorMsg)
                    }

                    // Delete error file
                    try AppGroups.deleteFile("error.json", in: AppGroups.Paths.control)
                }

            } catch {
                // Silently ignore errors
            }
        }
    }

    // MARK: - App Status

    /// Check main app status
    /// - Parameter completion: Completion handler with app status
    func checkAppStatus(completion: @escaping (AppStatus) -> Void) {
        ipcQueue.async {
            do {
                // Send ping signal
                self.sendControlSignal(.ping, sessionId: "status_check")

                // Wait a bit for response
                Thread.sleep(forTimeInterval: 0.1)

                // Read status file
                if AppGroups.fileExists(AppGroups.Files.statusFile, in: AppGroups.Paths.control) {
                    let data = try AppGroups.readData(
                        from: AppGroups.Files.statusFile,
                        in: AppGroups.Paths.control
                    )

                    let status = try data.decode(as: AppStatus.self)

                    DispatchQueue.main.async {
                        completion(status)
                    }
                } else {
                    // No status file - app might not be running
                    let defaultStatus = AppStatus(
                        isModelLoaded: false,
                        isProcessing: false,
                        currentSessionId: nil,
                        modelVariant: "unknown",
                        memoryUsageMB: 0
                    )

                    DispatchQueue.main.async {
                        completion(defaultStatus)
                    }
                }

            } catch {
                print("[IPCPipe] Failed to check app status: \(error)")

                // Return default status on error
                let defaultStatus = AppStatus(
                    isModelLoaded: false,
                    isProcessing: false,
                    currentSessionId: nil,
                    modelVariant: "unknown",
                    memoryUsageMB: 0
                )

                DispatchQueue.main.async {
                    completion(defaultStatus)
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Clean up old files
    func cleanupOldFiles() {
        ipcQueue.async {
            do {
                // Clean up audio buffers directory
                if let audioBuffersPath = AppGroups.Paths.audioBuffers {
                    let fileManager = FileManager.default
                    let files = try fileManager.contentsOfDirectory(
                        at: audioBuffersPath,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )

                    // Delete files older than 1 minute
                    let cutoffTime = Date().addingTimeInterval(-60)

                    for fileURL in files {
                        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                              let modDate = attributes[.modificationDate] as? Date else {
                            continue
                        }

                        if modDate < cutoffTime {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                }

            } catch {
                print("[IPCPipe] Failed to cleanup old files: \(error)")
            }
        }
    }
}
