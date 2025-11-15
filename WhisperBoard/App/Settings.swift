//
//  Settings.swift
//  WhisperBoard
//
//  Manages app settings and persists them to App Groups shared container
//  Settings are shared between main app and keyboard extension
//

import Foundation
import Combine

/// Settings manager for WhisperBoard
class Settings: ObservableObject {

    // MARK: - Published Properties

    @Published var settings: WhisperBoardSettings {
        didSet {
            saveSettings()
        }
    }

    // MARK: - Properties

    static let shared = Settings()

    private let settingsQueue = DispatchQueue(label: "com.whisperboard.settings", qos: .utility)

    // MARK: - Initialization

    private init() {
        // Load settings from shared container or use default
        self.settings = Self.loadSettings() ?? .default
    }

    // MARK: - Persistence

    /// Save settings to App Groups shared container
    private func saveSettings() {
        settingsQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let settingsData = try self.settings.toJSONData()

                try AppGroups.writeData(
                    settingsData,
                    to: AppGroups.Files.sharedSettings,
                    in: AppGroups.Paths.settings
                )

                print("[Settings] Saved settings to shared container")

            } catch {
                print("[Settings] Failed to save settings: \(error)")
            }
        }
    }

    /// Load settings from App Groups shared container
    private static func loadSettings() -> WhisperBoardSettings? {
        do {
            let settingsData = try AppGroups.readData(
                from: AppGroups.Files.sharedSettings,
                in: AppGroups.Paths.settings
            )

            let settings = try settingsData.decode(as: WhisperBoardSettings.self)
            print("[Settings] Loaded settings from shared container")
            return settings

        } catch {
            print("[Settings] Failed to load settings, using defaults: \(error)")
            return nil
        }
    }

    /// Reload settings from shared container (for extension to get updates)
    func reloadSettings() {
        if let loadedSettings = Self.loadSettings() {
            self.settings = loadedSettings
        }
    }

    // MARK: - Convenience Accessors

    var punctuationMode: WhisperBoardSettings.PunctuationMode {
        get { settings.punctuationMode }
        set { settings.punctuationMode = newValue }
    }

    var language: String? {
        get { settings.language }
        set { settings.language = newValue }
    }

    var enableVAD: Bool {
        get { settings.enableVAD }
        set { settings.enableVAD = newValue }
    }

    var vadThreshold: Float {
        get { settings.vadThreshold }
        set { settings.vadThreshold = newValue }
    }

    var streamingEnabled: Bool {
        get { settings.streamingEnabled }
        set { settings.streamingEnabled = newValue }
    }

    var chunkSizeMs: Int {
        get { settings.chunkSizeMs }
        set { settings.chunkSizeMs = newValue }
    }

    var maxRecordingDurationSec: Int {
        get { settings.maxRecordingDurationSec }
        set { settings.maxRecordingDurationSec = newValue }
    }

    // MARK: - Reset

    /// Reset to default settings
    func resetToDefaults() {
        settings = .default
    }
}
