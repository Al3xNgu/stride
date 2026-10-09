import DomainKit
import Foundation
import SwiftData

/// SwiftData-backed persistence for completed-run projections, splits, and
/// personal-best records.
@ModelActor
public actor SwiftDataRunHistoryRepository: RunHistoryRepository {
    public func upsert(_ run: CompletedRun) async throws {
        try wrapping {
            var descriptor = FetchDescriptor<CompletedRunModel>(
                predicate: #Predicate { $0.id == run.id }
            )
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                CompletedRunMapper.apply(run, to: existing)
            } else {
                modelContext.insert(CompletedRunMapper.toModel(run))
            }
            try modelContext.save()
        }
    }

    public func fetchAll() async throws -> [CompletedRun] {
        try wrapping {
            var descriptor = FetchDescriptor<CompletedRunModel>()
            descriptor.sortBy = [SortDescriptor(\.date, order: .reverse)]
            return try modelContext.fetch(descriptor).map(CompletedRunMapper.toDomain)
        }
    }

    public func fetch(id: UUID) async throws -> CompletedRun? {
        try wrapping {
            var descriptor = FetchDescriptor<CompletedRunModel>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first.map(CompletedRunMapper.toDomain)
        }
    }

    public func fetch(from startDate: Date, to endDate: Date) async throws -> [CompletedRun] {
        try wrapping {
            let descriptor = FetchDescriptor<CompletedRunModel>(
                predicate: #Predicate { $0.date >= startDate && $0.date <= endDate },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(CompletedRunMapper.toDomain)
        }
    }

    public func markDeleted(id: UUID) async throws {
        try wrapping {
            var descriptor = FetchDescriptor<CompletedRunModel>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let model = try modelContext.fetch(descriptor).first else {
                throw RunHistoryRepositoryError.runNotFound(id: id)
            }
            model.deletedFlag = true
            try modelContext.save()
        }
    }

    public func saveSplits(_ splits: [Split], for runID: UUID) async throws {
        try wrapping {
            var descriptor = FetchDescriptor<CompletedRunModel>(
                predicate: #Predicate { $0.id == runID }
            )
            descriptor.fetchLimit = 1
            let runModel = try modelContext.fetch(descriptor).first
            let oldSplits = try modelContext.fetch(
                FetchDescriptor<SplitModel>(predicate: #Predicate { $0.runID == runID })
            )
            let incomingIDs = Set(splits.map(\.id))
            for old in oldSplits where !incomingIDs.contains(old.id) {
                modelContext.delete(old)
            }
            let existingByID = Dictionary(uniqueKeysWithValues: oldSplits.map { ($0.id, $0) })
            for split in splits {
                if let existing = existingByID[split.id] {
                    existing.index = split.index
                    existing.distanceMeters = split.distanceMeters
                    existing.durationSeconds = split.durationSeconds
                    existing.run = runModel
                } else {
                    let model = SplitMapper.toModel(split)
                    model.run = runModel
                    modelContext.insert(model)
                }
            }
            try modelContext.save()
        }
    }

    public func fetchSplits(runID: UUID) async throws -> [Split] {
        try wrapping {
            let descriptor = FetchDescriptor<SplitModel>(
                predicate: #Predicate { $0.runID == runID },
                sortBy: [SortDescriptor(\.index)]
            )
            return try modelContext.fetch(descriptor).map(SplitMapper.toDomain)
        }
    }

    public func savePersonalBest(_ personalBest: PersonalBest) async throws {
        try wrapping {
            var descriptor = FetchDescriptor<PersonalBestModel>(
                predicate: #Predicate { $0.id == personalBest.id }
            )
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                PersonalBestMapper.apply(personalBest, to: existing)
            } else {
                modelContext.insert(PersonalBestMapper.toModel(personalBest))
            }
            try modelContext.save()
        }
    }

    public func fetchPersonalBests() async throws -> [PersonalBest] {
        try wrapping {
            try modelContext.fetch(FetchDescriptor<PersonalBestModel>()).map(PersonalBestMapper.toDomain)
        }
    }

    public func fetchPersonalBest(milestoneID: UUID) async throws -> PersonalBest? {
        try wrapping {
            let descriptor = FetchDescriptor<PersonalBestModel>(
                predicate: #Predicate { $0.milestoneID == milestoneID }
            )
            return try modelContext.fetch(descriptor)
                .map(PersonalBestMapper.toDomain)
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
    }

    public func deletePersonalBest(id: UUID) async throws {
        try wrapping {
            var descriptor = FetchDescriptor<PersonalBestModel>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
                try modelContext.save()
            }
        }
    }

    private func wrapping<T>(_ body: () throws -> T) throws -> T {
        modelContext.autosaveEnabled = false
        do {
            return try body()
        } catch let error as RunHistoryRepositoryError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw RunHistoryRepositoryError.underlying(String(describing: error))
        }
    }
}
