//
//  TranscriptionDisplay.swift
//  WhisperBoard Keyboard Extension
//
//  Handles displaying transcription results in the keyboard UI
//  Manages streaming updates and final results
//

import UIKit

/// Manages transcription display in keyboard extension
class TranscriptionDisplay {

    // MARK: - Properties

    private var currentText: String = ""
    private var isStreaming = false

    // MARK: - Display Management

    /// Update display with new transcription text
    /// - Parameters:
    ///   - text: New transcription text
    ///   - isFinal: Whether this is the final result
    func updateTranscription(_ text: String, isFinal: Bool) {
        currentText = text
        isStreaming = !isFinal

        print("[TranscriptionDisplay] Updated: \"\(text)\" (final: \(isFinal))")
    }

    /// Clear current transcription
    func clear() {
        currentText = ""
        isStreaming = false
    }

    /// Get current transcription text
    var text: String {
        return currentText
    }

    /// Format text for display with indicators
    var displayText: String {
        var display = currentText

        // Add streaming indicator if not final
        if isStreaming && !currentText.isEmpty {
            display += " ..."
        }

        return display
    }

    // MARK: - Animation Support

    /// Animate text appearance
    /// - Parameter label: Label to animate
    func animateTextUpdate(in label: UILabel) {
        UIView.transition(
            with: label,
            duration: 0.2,
            options: .transitionCrossDissolve,
            animations: {
                label.text = self.displayText
            }
        )
    }
}
