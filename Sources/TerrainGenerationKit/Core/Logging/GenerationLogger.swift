import Foundation

public final class GenerationLogger: @unchecked Sendable {
    public static let shared = GenerationLogger()

    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    private var _isEnabled: Bool = true
    private var stageTimers: [String: CFAbsoluteTime] = [:]

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer {
                lock.unlock()
            }
            return _isEnabled
        }
        set {
            lock.lock()
            defer {
                lock.unlock()
            }
            _isEnabled = newValue
        }
    }

    public var entries: [LogEntry] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return _entries
    }

    private init() {
    }

    public func clear() {
        lock.lock()
        defer {
            lock.unlock()
        }
        _entries.removeAll()
        stageTimers.removeAll()
    }

    public func log(stage: String, message: String) {
        guard isEnabled else {
            return
        }
        lock.lock()
        defer {
            lock.unlock()
        }
        let entry = LogEntry(stage: stage, message: message)
        _entries.append(entry)
        print("[\(stage)] \(message)")
    }

    public func startStage(_ stage: String) {
        guard isEnabled else {
            return
        }
        lock.lock()
        defer {
            lock.unlock()
        }
        stageTimers[stage] = CFAbsoluteTimeGetCurrent()
    }

    public func endStage(_ stage: String, message: String) {
        guard isEnabled else {
            return
        }
        lock.lock()
        defer {
            lock.unlock()
        }

        let duration: TimeInterval?
        if let startTime = stageTimers[stage] {
            duration = CFAbsoluteTimeGetCurrent() - startTime
            stageTimers.removeValue(forKey: stage)
        } else {
            duration = nil
        }

        let entry = LogEntry(stage: stage, message: message, duration: duration)
        _entries.append(entry)

        if let dur = duration {
            let ms = Int(dur * 1000)
            print("[\(stage)] \(message) – \(ms)ms")
        } else {
            print("[\(stage)] \(message)")
        }
    }
}
