import Foundation

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let stage: String
    public let message: String
    public let duration: TimeInterval?

    public init(stage: String, message: String, duration: TimeInterval? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.stage = stage
        self.message = message
        self.duration = duration
    }

    public var formattedDuration: String {
        guard let duration = duration else {
            return ""
        }
        let ms = Int(duration * 1000)
        return "\(ms)ms"
    }

    public var displayText: String {
        if let duration = duration {
            return "[\(stage)] \(message) – \(formattedDuration)"
        } else {
            return "[\(stage)] \(message)"
        }
    }
}
