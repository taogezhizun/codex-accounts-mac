import Foundation

/// Cadence for the saved account matching the live login. Other accounts retain their cache.
struct RefreshSchedule {
    static let interval: TimeInterval = 300
    private(set) var next: [String: Date] = [:]
    private(set) var failures: [String: Int] = [:]

    mutating func reconcile(_ ids: [String], now: Date) {
        let active = Set(ids)
        next = next.filter { active.contains($0.key) }
        failures = failures.filter { active.contains($0.key) }
        for id in ids where next[id] == nil { next[id] = now }
    }
    mutating func reconcileCurrent(_ currentID: String?, savedIDs: [String], now: Date) {
        let ids = currentID.map { savedIDs.contains($0) ? [$0] : [] } ?? []
        reconcile(ids, now: now)
    }
    func due(now: Date, enabled: Bool, blocked: Bool) -> String? {
        guard enabled, !blocked else { return nil }
        return next.filter { $0.value <= now }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
        }.first?.key
    }
    mutating func completed(_ id: String, succeeded: Bool, now: Date) {
        let count = succeeded ? 0 : min(4, (failures[id] ?? 0) + 1)
        failures[id] = count
        let delay = succeeded ? Self.interval : min(3600, Self.interval * pow(2, Double(count)))
        next[id] = now.addingTimeInterval(delay)
    }
    mutating func request(_ id: String, now: Date) { next[id] = now; failures[id] = 0 }
}
