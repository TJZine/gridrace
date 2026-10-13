import Foundation
import Observation

/// Nonsecret intent, outside Accounts/<UUID>. It grants no server authority.
struct AccountCleanupRecord: Codable, Equatable, Sendable {
    enum Daily: String, Codable, Sendable { case awaitingDeletion, required }
    let userID: UUID
    var daily: Daily?
    var live: Bool
    var invitationClearRequired: Bool? = nil
    var invitationGeneration: UUID? = nil
}

protocol AccountCleanupJournalStoring {
    func load() throws -> [AccountCleanupRecord]
    func save(_ records: [AccountCleanupRecord]) throws
}

struct AccountCleanupJournalFile: AccountCleanupJournalStoring {
    let directory: URL
    var url: URL { directory.appending(path: "account-cleanup-v1.json") }
    private struct Payload: Codable {
        let version: Int
        let records: [AccountCleanupRecord]
    }
    func load() throws -> [AccountCleanupRecord] {
        let bytes: Data
        do { bytes = try Data(contentsOf: url) }
        catch where PersistenceFile.isNotFound(error) { return [] }
        let payload = try JSONDecoder().decode(Payload.self, from: bytes)
        guard payload.version == 1,
              Set(payload.records.map(\.userID)).count == payload.records.count,
              payload.records.allSatisfy({ record in
                  (record.daily != nil || record.live || record.invitationClearRequired == true)
                      && (record.invitationClearRequired == true || record.invitationGeneration == nil)
                      && record.invitationGeneration != PendingLiveInvitation.unassignedGeneration
              }) else {
            throw JournalError.invalidData
        }
        return payload.records
    }
    func save(_ records: [AccountCleanupRecord]) throws {
        if records.isEmpty {
            do { try FileManager.default.removeItem(at: url) }
            catch where PersistenceFile.isNotFound(error) {}
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(Payload(version: 1, records: records))
            try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
    private enum JournalError: Error { case invalidData }
}

@MainActor
@Observable
final class AccountCleanupJournal {
    private let storage: any AccountCleanupJournalStoring
    private(set) var records: [AccountCleanupRecord] = []
    private(set) var isUnavailable = false
    private var loaded = false
    init(storage: any AccountCleanupJournalStoring) {
        self.storage = storage
        try? reload()
    }
    func reload() throws {
        do {
            let disk = try storage.load()
            // A failed write retains captured intent in memory. Merge it only after
            // a successful read, never overwrite a journal we could not inspect.
            var merged = Dictionary(uniqueKeysWithValues: disk.map { ($0.userID, $0) })
            for record in records {
                if var existing = merged[record.userID] {
                    existing.live = existing.live || record.live
                    if record.invitationClearRequired == true {
                        existing.invitationClearRequired = true
                        existing.invitationGeneration = record.invitationGeneration
                    }
                    if record.daily == .required || existing.daily == nil { existing.daily = record.daily }
                    merged[record.userID] = existing
                } else { merged[record.userID] = record }
            }
            records = merged.values.sorted { $0.userID.uuidString < $1.userID.uuidString }
            loaded = true
            isUnavailable = false
        } catch { isUnavailable = true; throw error }
    }
    private func persist() throws {
        do { try storage.save(records); isUnavailable = false }
        catch { isUnavailable = true; throw error }
    }
    func capture(_ userID: UUID, deleting: Bool) throws {
        if !loaded { try reload() }
        if let index = records.firstIndex(where: { $0.userID == userID }) {
            records[index].live = true
            if deleting && records[index].daily == nil { records[index].daily = .awaitingDeletion }
        } else {
            records.append(AccountCleanupRecord(userID: userID, daily: deleting ? .awaitingDeletion : nil, live: true))
        }
        try persist()
    }
    func confirmDeletion(_ userID: UUID) throws {
        if !loaded { try reload() }
        guard let index = records.firstIndex(where: { $0.userID == userID }) else {
            throw JournalError.missingIntent
        }
        records[index].daily = .required
        try persist()
    }
    func completeDaily(_ userID: UUID) throws { try complete(userID, daily: true) }
    func completeLive(_ userID: UUID) throws { try complete(userID, daily: false) }
    private func complete(_ userID: UUID, daily: Bool) throws {
        if !loaded { try reload() }
        let original = records
        if let index = records.firstIndex(where: { $0.userID == userID }) {
            if daily { records[index].daily = nil } else { records[index].live = false }
            records.removeAll { $0.daily == nil && !$0.live && $0.invitationClearRequired != true }
        }
        do { try persist() }
        catch { records = original; throw error } // Removal proof may safely be retried.
    }
    func captureInvitation(_ userID: UUID, generation: UUID?, replacingCapturedValue: Bool = false) throws {
        if !loaded { try reload() }
        if let index = records.firstIndex(where: { $0.userID == userID }) {
            // Retry preserves the captured generation. A new explicit departure
            // captures the current value, including navigation saved during old cleanup.
            if records[index].invitationClearRequired != true || replacingCapturedValue {
                records[index].invitationClearRequired = true
                records[index].invitationGeneration = generation
            }
        } else {
            records.append(AccountCleanupRecord(userID: userID, daily: nil, live: false,
                                                invitationClearRequired: true, invitationGeneration: generation))
        }
        try persist()
    }
    func completeInvitation(_ userID: UUID) throws {
        if !loaded { try reload() }
        let original = records
        if let index = records.firstIndex(where: { $0.userID == userID }) {
            records[index].invitationClearRequired = nil
            records[index].invitationGeneration = nil
            records.removeAll { $0.daily == nil && !$0.live && $0.invitationClearRequired != true }
        }
        do { try persist() } catch { records = original; throw error }
    }
    var invitationUsers: Set<UUID> { Set(records.filter { $0.invitationClearRequired == true }.map(\.userID)) }
    var dailyUsers: Set<UUID> { Set(records.filter { $0.daily == .required }.map(\.userID)) }
    var liveUsers: Set<UUID> { Set(records.filter(\.live).map(\.userID)) }
    private enum JournalError: Error { case missingIntent }
}
