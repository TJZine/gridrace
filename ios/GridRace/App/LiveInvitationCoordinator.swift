import Foundation
import Observation

struct LiveInvitationConfiguration: Sendable {
    let origins: [URL]
    var parser: LiveInvitationParser? { try? LiveInvitationParser(allowedOrigins: origins) }
    init(origins: [URL]) { self.origins = origins }
    static func configured(bundle: Bundle = .main) -> Self {
        let values = (bundle.object(forInfoDictionaryKey: "GridRaceInvitationOrigins") as? String ?? "")
            .split(separator: " ").map(String.init)
        guard !values.isEmpty, !values.contains(where: { $0.contains("$(") }),
              values.allSatisfy({ LiveInvitationParser.normalizedOrigin($0) != nil }) else { return Self(origins: []) }
        return Self(origins: values.compactMap(URL.init(string:)))
    }
    func shareURL(code: String) -> URL? {
        guard let origin = origins.first.flatMap({ LiveInvitationParser.normalizedOrigin($0.absoluteString) }),
              let code = LiveInvitationParser.canonicalCode(code), let parser,
              let url = URL(string: "\(origin)/join/\(code)"), parser.parse(url) != nil else { return nil }
        return url
    }
}

struct LiveInvitationJoinConfirmation: Equatable {
    let invitation: PendingLiveInvitation
    let userID: UUID
    let sourceMatchID: UUID?
}

@MainActor
@Observable
final class LiveInvitationCoordinator {
    let configuration: LiveInvitationConfiguration
    let cleanupJournal: AccountCleanupJournal
    private let makeStore: () throws -> PendingLiveInvitationStore
    private var store: PendingLiveInvitationStore?
    private(set) var pending: PendingLiveInvitation?
    private(set) var replacement: PendingLiveInvitation?
    private var replacementApproved = false
    private var unsaved: PendingLiveInvitation?
    private(set) var storageFailed = false
    var invalidLink = false
    var isPresented = false
    private var boundUserID: UUID?
    private var acknowledgmentFailed = false
    private weak var live: LiveMatchSession?
    private var fencedUser: UUID?
    private var admissionClearGeneration: UUID?
    private var admissionClearUser: UUID?
    private var fencedGeneration: UUID?

    init(configuration: LiveInvitationConfiguration = .configured(),
         cleanupJournal: AccountCleanupJournal,
         makeStore: @escaping () throws -> PendingLiveInvitationStore) {
        self.configuration = configuration
        self.cleanupJournal = cleanupJournal
        self.makeStore = makeStore
        restore()
    }
    static func applicationSupport() -> LiveInvitationCoordinator {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GridRace", directoryHint: .isDirectory)
        return LiveInvitationCoordinator(cleanupJournal: AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: directory)),
                                         makeStore: { PendingLiveInvitationStore(directory: directory) })
    }
    var cleanupBlocked: Bool { cleanupJournal.isUnavailable || !cleanupJournal.invitationUsers.isEmpty }
    var configurationRejectsPending: Bool {
        guard let pending, let url = URL(string: "\(pending.origin)/join/\(pending.code)") else { return false }
        return configuration.parser?.parse(url) == nil
    }
    var visiblePending: PendingLiveInvitation? { cleanupBlocked || configurationRejectsPending ? nil : pending }
    var needsAttention: Bool { storageFailed || cleanupBlocked || configurationRejectsPending || invalidLink || replacement != nil }

    func receive(_ url: URL) {
        guard let invitation = configuration.parser?.parse(url) else { invalidLink = true; isPresented = true; return }
        invalidLink = false
        replacementApproved = false
        do {
            let store = try storage()
            pending = try store.load()
            if pending?.code == invitation.code { return }
            if pending != nil { replacement = invitation; isPresented = true; return }
            unsaved = invitation
            try persistArrival()
        } catch { unsaved = invitation; storageFailed = true; isPresented = true }
    }
    func keepCurrent() { replacement = nil; isPresented = true }
    func replace() {
        guard let replacement else { return }
        do {
            let durable = try storage().load()
            guard durable == pending else {
                pending = durable
                isPresented = true
                return
            }
        } catch { storageFailed = true; return }
        unsaved = replacement
        replacementApproved = true
        do { try persistArrival(); self.replacement = nil } catch { storageFailed = true }
    }
    private func persistArrival() throws {
        guard let unsaved else { return }
        guard !cleanupJournal.records.contains(where: { $0.invitationClearRequired == true && $0.invitationGeneration == nil }) else {
            throw PendingLiveInvitationStoreError.unavailable
        }
        let result = try storage().save(unsaved)
        switch result {
        case .duplicate(let value): pending = value
        case .saved(let value), .replaced(let value):
            pending = value
            fencedGeneration = live == nil ? nil : value.replacementGeneration
            live?.invitationNavigationChanged()
        }
        self.unsaved = nil
        storageFailed = false
        isPresented = !cleanupBlocked
    }
    func restore() {
        do { pending = try storage().load(); storageFailed = false }
        catch { storageFailed = true }
    }
    func retry(recoverAcknowledgment: Bool = true) {
        acknowledgmentFailed = false
        do {
            try cleanupJournal.reload()
            if let generation = admissionClearGeneration {
                if let user = admissionClearUser { try cleanupJournal.captureInvitation(user, generation: generation) }
                else { try storage().clear(matchingGeneration: generation) }
            }
            for record in cleanupJournal.records where record.invitationClearRequired == true {
                if let generation = record.invitationGeneration { try storage().clear(matchingGeneration: generation) }
                else { try storage().clear() }
                try cleanupJournal.completeInvitation(record.userID)
            }
            pending = try storage().load()
            if recoverAcknowledgment, let live, boundUserID == admissionClearUser,
               live.completedInvitationAccountID == admissionClearUser,
               live.completedInvitationGeneration == admissionClearGeneration,
               live.phase == .storageUnavailable {
                live.retry()
            }
            try acknowledgeAdmission()
            if let unsaved, let pending, pending.code != unsaved.code, !replacementApproved {
                replacement = unsaved
                self.unsaved = nil
                isPresented = true
            } else if unsaved != nil { try persistArrival() }
            storageFailed = false
        } catch { storageFailed = true }
    }
    func prepareForAccountDeparture(_ userID: UUID) throws {
        let value = try? storage().load()
        try cleanupJournal.captureInvitation(userID, generation: value?.replacementGeneration, replacingCapturedValue: true)
        isPresented = false
        replacement = nil
        unsaved = nil
        retry(recoverAcknowledgment: false)
    }
    func discard() {
        if let live, let generation = live.completedInvitationGeneration,
           let owner = live.completedInvitationAccountID, owner == boundUserID {
            admissionClearGeneration = generation; admissionClearUser = owner
        }
        do {
            try storage().clear()
            for user in cleanupJournal.invitationUsers { try cleanupJournal.completeInvitation(user) }
            pending = nil; replacement = nil; unsaved = nil
            try acknowledgeAdmission()
            storageFailed = false; invalidLink = false; isPresented = false
        } catch { storageFailed = true }
    }
    func admitted(generation: UUID, userID: UUID? = nil) {
        if let live, let userID,
           (boundUserID != userID || live.completedInvitationAccountID != userID || live.completedInvitationGeneration != generation) { return }
        admissionClearGeneration = generation; admissionClearUser = userID
        acknowledgmentFailed = false
        do {
            let stored = try storage().load()
            if stored?.replacementGeneration == generation {
                if let userID { try cleanupJournal.captureInvitation(userID, generation: generation) }
                try storage().clear(matchingGeneration: generation)
            }
            if let userID { try cleanupJournal.completeInvitation(userID) }
            pending = try storage().load()
            try acknowledgeAdmission()
            storageFailed = false
        } catch { storageFailed = true }
    }
    private func acknowledgeAdmission() throws {
        guard let generation = admissionClearGeneration else { return }
        if let live, let userID = admissionClearUser, boundUserID == userID,
           live.completedInvitationAccountID == userID, live.completedInvitationGeneration == generation {
            guard live.acknowledgeInvitationClear(matchingGeneration: generation, forAccount: userID) else {
                acknowledgmentFailed = true
                throw PendingLiveInvitationStoreError.unavailable
            }
        }
        admissionClearGeneration = nil; admissionClearUser = nil
        acknowledgmentFailed = false
    }
    func bind(_ live: LiveMatchSession, userID: UUID?) {
        self.live = live
        boundUserID = userID
        if admissionClearUser != nil, admissionClearUser != userID {
            admissionClearGeneration = nil; admissionClearUser = nil
            if acknowledgmentFailed { storageFailed = false; acknowledgmentFailed = false }
        }
        if live.phase != .storageUnavailable,
           let generation = live.completedInvitationGeneration, let owner = live.completedInvitationAccountID, owner == userID {
            admitted(generation: generation, userID: owner)
        }
        guard let userID, let pending, !cleanupBlocked, live.phase != .storageUnavailable,
              fencedUser != userID || fencedGeneration != pending.replacementGeneration else { return }
        live.invitationNavigationChanged()
        fencedUser = userID; fencedGeneration = pending.replacementGeneration
    }
    func fenceForLiveEntry() {
        if pending != nil { live?.invitationNavigationChanged() }
    }
    func confirmation(for app: DailyAccountCoordinator) -> LiveInvitationJoinConfirmation? {
        guard let invitation = visiblePending, !storageFailed, replacement == nil,
              let userID = app.account.session?.userID, app.account.profile?.userID == userID,
              !app.account.needsProfileSetup, !app.account.isWorking, !app.account.isLoadingProfile,
              app.account.authRecovery == nil, app.live.phase != .storageUnavailable, app.live.phase != .needsSignIn,
              app.live.pendingIntent == nil, !app.live.serviceNeedsUpdate, app.live.completedInvitationGeneration == nil, !app.live.hasPendingStart, !app.live.isCommandInFlight else { return nil }
        return LiveInvitationJoinConfirmation(invitation: invitation, userID: userID, sourceMatchID: app.live.savedMatchID)
    }
    @discardableResult
    func join(_ confirmation: LiveInvitationJoinConfirmation, app: DailyAccountCoordinator) -> Bool {
        guard self.confirmation(for: app) == confirmation else { return false }
        do {
            let durable = try storage().load()
            guard durable == confirmation.invitation else { pending = durable; return false }
        } catch { storageFailed = true; return false }
        app.live.joinMatch(code: confirmation.invitation.code,
                           invitationGeneration: confirmation.invitation.replacementGeneration)
        guard case .join = app.live.pendingIntent else { return false }
        isPresented = false
        return true
    }
    private func storage() throws -> PendingLiveInvitationStore {
        if let store { return store }
        let created = try makeStore(); store = created; return created
    }
}
