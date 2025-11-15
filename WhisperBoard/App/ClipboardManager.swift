//
//  ClipboardManager.swift
//  WhisperBoard
//
//  Handles clipboard operations for fallback transcription mode
//  When custom keyboard is blocked, users can copy transcription to clipboard
//

import UIKit

/// Manages clipboard operations for transcription fallback
class ClipboardManager {

    // MARK: - Properties

    private let pasteboard = UIPasteboard.general

    // MARK: - Clipboard Operations

    /// Copy text to clipboard
    /// - Parameter text: Text to copy
    func copyToClipboard(_ text: String) {
        pasteboard.string = text
        print("[ClipboardManager] Copied to clipboard: \"\(text)\"")
    }

    /// Get text from clipboard
    /// - Returns: Text from clipboard, or nil if none
    func getFromClipboard() -> String? {
        return pasteboard.string
    }

    /// Clear clipboard
    func clearClipboard() {
        pasteboard.string = ""
    }

    /// Check if clipboard has text
    var hasText: Bool {
        return pasteboard.hasStrings
    }

    // MARK: - Transcription Helpers

    /// Copy transcription result to clipboard with optional formatting
    /// - Parameters:
    ///   - result: Transcription result
    ///   - includeMetadata: Whether to include metadata in clipboard (default: false)
    func copyTranscription(_ result: TranscriptionResult, includeMetadata: Bool = false) {
        var clipboardText = result.text

        if includeMetadata {
            let metadata = """

            ---
            [Transcribed by WhisperBoard]
            Session: \(result.sessionId)
            Time: \(result.timestamp)
            Processing: \(result.processingTimeMs)ms
            """
            clipboardText += metadata
        }

        copyToClipboard(clipboardText)
    }

    /// Show system notification that text was copied
    /// - Parameter text: Text that was copied
    func showCopiedNotification(for text: String) {
        // Create haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Could also show banner notification if using UserNotifications framework
        print("[ClipboardManager] ✓ Copied: \(text)")
    }
}
