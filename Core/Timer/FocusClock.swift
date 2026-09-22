import Foundation

enum FocusPhase: String, Codable, Equatable, Sendable {
    case focus
    case shortBreak
    case longBreak
}

enum FocusRunState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
}

struct FocusDurations: Equatable, Sendable {
    var focus: TimeInterval
    var shortBreak: TimeInterval
    var longBreak: TimeInterval
    var longBreakEvery: Int
    var rottenBefore: TimeInterval

    static let standard = FocusDurations(
        focus: 25 * 60,
        shortBreak: 5 * 60,
        longBreak: 15 * 60,
        longBreakEvery: 4,
        rottenBefore: 10 * 60
    )

    func length(of phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

enum ClockEvent: Equatable, Sendable {
    case none
    case focusFinished(elapsed: TimeInterval, rotten: Bool, counts: Bool, sessionID: String?)
    case breakFinished
}

struct FocusClock: Equatable, Sendable, Codable {
    var phase: FocusPhase = .focus
    var runState: FocusRunState = .idle
    var endDate: Date?
    var pausedRemaining: TimeInterval?
    var completedFocusCount: Int = 0
    var segmentStartedAt: Date?
    var accrued: TimeInterval = 0
    var budget: TimeInterval = 25 * 60
        var boardID: String?
        var cardID: String?
        var activeSessionID: String?

    static let storageKey = "tempo.clock"

    func remaining(at now: Date, durations: FocusDurations) -> TimeInterval {
        switch runState {
        case .running:
            guard let endDate else { return budget }
            return max(0, endDate.timeIntervalSince(now))
        case .paused:
            return max(0, pausedRemaining ?? budget)
        case .idle:
            return durations.length(of: phase)
        }
    }

    func progress(at now: Date, durations: FocusDurations) -> Double {
        let total = runState == .idle ? durations.length(of: phase) : max(budget, 1)
        let done = total - remaining(at: now, durations: durations)
        return min(1, max(0, done / total))
    }

    mutating func start(at now: Date, durations: FocusDurations) {
        if runState == .paused {
            resume(at: now)
            return
        }
        guard runState == .idle else { return }
        if phase == .focus, activeSessionID == nil {
            activeSessionID = UUID().uuidString
        }
        accrued = 0
        budget = durations.length(of: phase)
        segmentStartedAt = now
        endDate = now.addingTimeInterval(budget)
        pausedRemaining = nil
        runState = .running
    }

    mutating func pause(at now: Date, durations: FocusDurations) {
        guard runState == .running else { return }
        accrued = activeElapsed(at: now)
        pausedRemaining = remaining(at: now, durations: durations)
        segmentStartedAt = nil
        endDate = nil
        runState = .paused
    }

    mutating func resume(at now: Date) {
        guard runState == .paused else { return }
        let remain = max(0, pausedRemaining ?? 0)
        segmentStartedAt = now
        endDate = now.addingTimeInterval(remain)
        pausedRemaining = nil
        runState = .running
    }

    mutating func extend(by extra: TimeInterval, at now: Date) {
        guard phase == .focus, extra > 0, runState != .idle else { return }
        budget += extra
        if runState == .running, let endDate {
            self.endDate = endDate.addingTimeInterval(extra)
        } else if runState == .paused {
            pausedRemaining = (pausedRemaining ?? 0) + extra
        }
    }

    mutating func stop() -> String? {
        let discarded = activeSessionID
        phase = .focus
        runState = .idle
        endDate = nil
        pausedRemaining = nil
        segmentStartedAt = nil
        accrued = 0
        budget = 25 * 60
        activeSessionID = nil
        return discarded
    }

    mutating func skip(at now: Date, durations: FocusDurations) -> ClockEvent {
        guard runState != .idle else {
            advance(durations: durations)
            return .none
        }
        return finishSegment(at: now, durations: durations, natural: false)
    }

    mutating func switchPhase(durations: FocusDurations) {
        guard runState == .idle else { return }
        switch phase {
        case .focus:
            phase = .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
        budget = durations.length(of: phase)
        accrued = 0
        pausedRemaining = nil
        endDate = nil
        segmentStartedAt = nil
        activeSessionID = nil
    }

    mutating func reconcile(at now: Date, durations: FocusDurations) -> ClockEvent {
        guard runState == .running, let endDate, now >= endDate else { return .none }
        return finishSegment(at: endDate, durations: durations, natural: true)
    }

    func activeElapsed(at now: Date) -> TimeInterval {
        var total = accrued
        if runState == .running, let segmentStartedAt {
            total += max(0, now.timeIntervalSince(segmentStartedAt))
        }
        return min(max(0, total), budget)
    }

    static func load(defaults: UserDefaults = .standard) -> FocusClock {
        guard let data = defaults.data(forKey: storageKey),
              let clock = try? JSONDecoder().decode(FocusClock.self, from: data) else {
            return FocusClock()
        }
        return clock
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private mutating func finishSegment(at now: Date, durations: FocusDurations, natural: Bool) -> ClockEvent {
        let elapsed = min(activeElapsed(at: now), budget)
        let finished = phase
        let sessionID = activeSessionID
        let rotten = finished == .focus && !natural && elapsed < durations.rottenBefore
        let counts = finished == .focus && (natural || elapsed >= durations.rottenBefore)
        if counts {
            completedFocusCount += 1
        }
        advance(durations: durations)
        if finished == .focus {
            return .focusFinished(elapsed: elapsed, rotten: rotten, counts: counts, sessionID: sessionID)
        }
        return .breakFinished
    }

    private mutating func advance(durations: FocusDurations) {
        switch phase {
        case .focus:
            let useLong = durations.longBreakEvery > 0
                && completedFocusCount > 0
                && completedFocusCount.isMultiple(of: durations.longBreakEvery)
            phase = useLong ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
        runState = .idle
        endDate = nil
        pausedRemaining = nil
        segmentStartedAt = nil
        accrued = 0
        activeSessionID = nil
        budget = durations.length(of: phase)
    }
}
