import DomainKit
import Foundation

/// An in-memory `RunHistoryRepository` fake.
///
/// Backed by plain dictionaries keyed by id, with an injectable
/// `errorToThrow` that every method checks first (CLAUDE.md rule 5).
///
/// Not internally synchronized: intended for single-threaded test usage.
public final class FakeRunHistoryRepository: RunHistoryRepository, @unchecked Sendable {
    /// Backing storage for completed runs, keyed by `CompletedRun.id`.
    public var runsByID: [UUID: CompletedRun]
    /// Backing storage for personal bests, keyed by `PersonalBest.id`.
    public var personalBestsByID: [UUID: PersonalBest]
    /// Backing storage for splits, keyed by the `CompletedRun.id` they
    /// belong to.
    public var splitsByRunID: [UUID: [Split]]
    /// When set, every call throws this error instead of succeeding.
    public var errorToThrow: Error?

    /// Creates a fake run history repository pre-seeded with `runs` and
    /// `personalBests`.
    public init(runs: [CompletedRun] = [], personalBests: [PersonalBest] = []) {
        self.runsByID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        self.personalBestsByID = Dictionary(uniqueKeysWithValues: personalBests.map { ($0.id, $0) })
        self.splitsByRunID = [:]
    }

    public func upsert(_ run: CompletedRun) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        runsByID[run.id] = run
    }

    public func fetchAll() async throws -> [CompletedRun] {
        if let errorToThrow {
            throw errorToThrow
        }
        return Array(runsByID.values)
    }

    public func fetch(id: UUID) async throws -> CompletedRun? {
        if let errorToThrow {
            throw errorToThrow
        }
        return runsByID[id]
    }

    public func fetch(from startDate: Date, to endDate: Date) async throws -> [CompletedRun] {
        if let errorToThrow {
            throw errorToThrow
        }
        return runsByID.values.filter { (startDate...endDate).contains($0.date) }
    }

    public func markDeleted(id: UUID) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        guard var run = runsByID[id] else {
            throw RunHistoryRepositoryError.runNotFound(id: id)
        }
        run.isDeleted = true
        runsByID[id] = run
    }

    public func saveSplits(_ splits: [Split], for runID: UUID) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        splitsByRunID[runID] = splits
    }

    public func fetchSplits(runID: UUID) async throws -> [Split] {
        if let errorToThrow {
            throw errorToThrow
        }
        return (splitsByRunID[runID] ?? []).sorted { $0.index < $1.index }
    }

    public func savePersonalBest(_ personalBest: PersonalBest) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        personalBestsByID[personalBest.id] = personalBest
    }

    public func fetchPersonalBests() async throws -> [PersonalBest] {
        if let errorToThrow {
            throw errorToThrow
        }
        return Array(personalBestsByID.values)
    }

    public func fetchPersonalBest(milestoneID: UUID) async throws -> PersonalBest? {
        if let errorToThrow {
            throw errorToThrow
        }
        // Deterministic "current" record per the port's documented contract:
        // lowest elapsedSeconds, ties by latest achievedAt, ties by
        // id.uuidString ascending.
        return personalBestsByID.values
            .filter { $0.milestoneID == milestoneID }
            .min { lhs, rhs in
                if lhs.elapsedSeconds != rhs.elapsedSeconds {
                    return lhs.elapsedSeconds < rhs.elapsedSeconds
                }
                if lhs.achievedAt != rhs.achievedAt {
                    return lhs.achievedAt > rhs.achievedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func deletePersonalBest(id: UUID) async throws {
        if let errorToThrow {
            throw errorToThrow
        }
        personalBestsByID.removeValue(forKey: id)
    }
}
