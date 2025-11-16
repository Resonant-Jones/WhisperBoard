//
//  Logger.swift
//  WhisperBoard
//
//  Structured logging framework for debugging and production monitoring
//

import Foundation

/// Log levels for filtering messages
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Structured logger for WhisperBoard
class Logger {

    // MARK: - Configuration

    /// Minimum log level to display (DEBUG shows all, ERROR shows only errors)
    static var minimumLevel: LogLevel = .debug

    /// Enable file logging (for production debugging)
    static var fileLoggingEnabled = false

    /// Log file URL
    private static var logFileURL: URL? {
        guard let containerURL = AppGroups.containerURL else { return nil }
        return containerURL.appendingPathComponent("Logs").appendingPathComponent("whisperboard.log")
    }

    // MARK: - Logging Methods

    /// Log a message with context
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Log level (default: .info)
    ///   - category: Category/component (e.g., "ModelLoader", "AudioProcessor")
    ///   - file: Source file (auto-filled)
    ///   - function: Source function (auto-filled)
    ///   - line: Source line (auto-filled)
    static func log(
        _ message: String,
        level: LogLevel = .info,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Skip if below minimum level
        guard level >= minimumLevel else { return }

        let filename = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let timestamp = dateFormatter.string(from: Date())

        // Build log message
        var logMessage = "[\(timestamp)] [\(level.emoji) \(level.name)]"

        if let category = category {
            logMessage += " [\(category)]"
        } else {
            logMessage += " [\(filename)]"
        }

        logMessage += " \(message)"

        #if DEBUG
        logMessage += " (\(filename).\(function):\(line))"
        #endif

        // Print to console
        print(logMessage)

        // Write to file if enabled
        if fileLoggingEnabled {
            writeToFile(logMessage)
        }
    }

    /// Log debug message
    static func debug(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    /// Log info message
    static func info(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    /// Log warning message
    static func warning(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    /// Log error message
    static func error(_ message: String, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    /// Log error with Error object
    static func error(_ error: Error, context: String? = nil, category: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let message = context != nil ? "\(context!): \(error.localizedDescription)" : error.localizedDescription
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - File Logging

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        DispatchQueue.global(qos: .utility).async {
            do {
                // Create logs directory if needed
                let logsDir = logFileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: logsDir.path) {
                    try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
                }

                // Append to log file
                let logLine = message + "\n"
                if let data = logLine.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logFileURL.path) {
                        let fileHandle = try FileHandle(forWritingTo: logFileURL)
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    } else {
                        try data.write(to: logFileURL)
                    }
                }

                // Rotate log if too large (> 5MB)
                rotateLogIfNeeded()
            } catch {
                print("Failed to write log to file: \(error)")
            }
        }
    }

    private static func rotateLogIfNeeded() {
        guard let logFileURL = logFileURL else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > 5_000_000 {
                // Archive old log
                let archiveURL = logFileURL.deletingLastPathComponent()
                    .appendingPathComponent("whisperboard_\(Int(Date().timeIntervalSince1970)).log")
                try FileManager.default.moveItem(at: logFileURL, to: archiveURL)

                // Delete archives older than 7 days
                let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
                let logsDir = logFileURL.deletingLastPathComponent()
                let files = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey])

                for file in files where file.lastPathComponent.starts(with: "whisperboard_") {
                    if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < cutoff {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        } catch {
            // Ignore rotation errors
        }
    }
}
