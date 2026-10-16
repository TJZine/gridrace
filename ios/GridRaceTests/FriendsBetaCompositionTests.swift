import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import GridRace

@MainActor
final class FriendsBetaCompositionTests: XCTestCase {
    private let origin = URL(string: "https://invite.test")!
    private func url(_ code: String = "ABC234") -> URL { URL(string: "https://invite.test/join/\(code)")! }
    private func owner(_ file: InvitationFaultFile, journal: InvitationJournalFile = InvitationJournalFile()) -> LiveInvitationCoordinator {
        LiveInvitationCoordinator(configuration: .init(origins: [origin]),
            cleanupJournal: AccountCleanupJournal(storage: journal), makeStore: { PendingLiveInvitationStore(persistence: file) })
    }

    func testIngressDuplicateInvalidAndExplicitReplacementNeverJoinOrLoseOldGeneration() throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url())
        let first = try XCTUnwrap(invitations.pending)
        let bytes = file.bytes
        invitations.isPresented = false
        invitations.receive(url("abc234"))
        XCTAssertFalse(invitations.isPresented)
        XCTAssertEqual(file.bytes, bytes)
        invitations.receive(URL(string: "https://wrong.test/join/ABC234")!)
        XCTAssertTrue(invitations.invalidLink)
        XCTAssertEqual(file.bytes, bytes)
        invitations.receive(url("DEF567"))
        XCTAssertEqual(invitations.pending, first)
        XCTAssertEqual(invitations.replacement?.code, "DEF567")
        invitations.keepCurrent()
        XCTAssertEqual(file.bytes, bytes)
        invitations.receive(url("DEF567"))
        invitations.replace()
        XCTAssertEqual(invitations.pending?.code, "DEF567")
        XCTAssertNotEqual(invitations.pending?.replacementGeneration, first.replacementGeneration)
        invitations.admitted(generation: first.replacementGeneration)
        XCTAssertEqual(invitations.pending?.code, "DEF567")
        XCTAssertEqual(owner(file).pending, invitations.pending)
    }
    func testReplacementDecisionRechecksDurableCurrentGeneration() throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url()); invitations.receive(url("DEF567"))
        let otherScene = owner(file)
        otherScene.receive(url("GHJ789")); otherScene.replace()
        invitations.replace()
        XCTAssertEqual(invitations.pending?.code, "GHJ789")
        XCTAssertEqual(invitations.replacement?.code, "DEF567")
        XCTAssertEqual(owner(file).pending?.code, "GHJ789", "Old confirmation must not replace a newer value")
        invitations.replace()
        XCTAssertEqual(owner(file).pending?.code, "DEF567")
    }
    func testFailedSaveRetryAndUnreadableExistingValueRequireReplacementDecision() throws {
        let file = InvitationFaultFile(), first = owner(file)
        file.rejectWrite = true
        first.receive(url())
        XCTAssertNil(first.pending)
        XCTAssertTrue(first.storageFailed)
        file.rejectWrite = false
        first.retry()
        XCTAssertEqual(first.pending?.code, "ABC234")
        let original = file.bytes
        file.rejectRead = true
        let unavailable = owner(file)
        unavailable.receive(url("DEF567"))
        XCTAssertTrue(unavailable.storageFailed)
        file.rejectRead = false
        unavailable.retry()
        XCTAssertEqual(file.bytes, original, "Recovering storage is not replacement consent")
        XCTAssertEqual(unavailable.replacement?.code, "DEF567")
        unavailable.replace()
        XCTAssertEqual(unavailable.pending?.code, "DEF567")
    }
    func testCorruptStoreRetryPreservesBytesAndDiscardIsExplicit() {
        let file = InvitationFaultFile(); file.bytes = Data("corrupt".utf8)
        let invitations = owner(file)
        invitations.receive(url())
        invitations.retry()
        XCTAssertEqual(file.bytes, Data("corrupt".utf8))
        XCTAssertNil(invitations.pending)
        invitations.discard()
        XCTAssertNil(file.bytes)
        XCTAssertFalse(invitations.storageFailed)
    }
    func testFailedDepartureClearIsHiddenDurableAndNewArrivalSurvivesOriginalCleanup() throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile(), user = UUID()
        let first = owner(file, journal: journal)
        first.receive(url())
        file.rejectRemove = true
        try first.prepareForAccountDeparture(user)
        XCTAssertNil(first.visiblePending)
        XCTAssertTrue(first.cleanupBlocked)
        let cold = owner(file, journal: journal)
        XCTAssertNil(cold.visiblePending)
        XCTAssertTrue(cold.cleanupBlocked)
        cold.receive(url("DEF567"))
        cold.replace()
        XCTAssertEqual(cold.pending?.code, "DEF567")
        XCTAssertNil(cold.visiblePending)
        file.rejectRemove = false
        cold.retry()
        XCTAssertEqual(cold.visiblePending?.code, "DEF567")
        XCTAssertFalse(cold.cleanupBlocked)
        XCTAssertTrue(journal.records.isEmpty)
    }
    func testNewExplicitDepartureClearsNewNavigationSavedDuringPriorCleanup() throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile(), invitations = owner(file, journal: journal), user = UUID()
        invitations.receive(url()); file.rejectRemove = true
        try invitations.prepareForAccountDeparture(user)
        invitations.receive(url("DEF567")); invitations.replace()
        let latest = try XCTUnwrap(invitations.pending?.replacementGeneration)
        try invitations.prepareForAccountDeparture(user)
        XCTAssertEqual(journal.records.first?.invitationGeneration, latest)
        file.rejectRemove = false
        let cold = owner(file, journal: journal); cold.retry()
        XCTAssertNil(cold.pending)
    }
    func testFailedJournalCaptureStopsAccountDepartureAndPreservesGuestAndInvitation() async throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile(), invitations = owner(file, journal: journal)
        invitations.receive(url())
        let service = AccountServiceMock(), user = UUID()
        service.restoredSession = AccountSession(userID: user, expiresAt: .distantFuture)
        service.loadedProfile = profile(user)
        let model = AccountModel(service: service, willDepartAccount: invitations.prepareForAccountDeparture)
        await model.start()
        journal.rejectWrite = true
        await model.signOut()
        XCTAssertEqual(service.signOutCount, 0)
        XCTAssertEqual(model.session?.userID, user)
        XCTAssertNotNil(file.bytes)
        XCTAssertTrue(invitations.cleanupBlocked)
        journal.rejectWrite = false
        await model.signOut()
        XCTAssertEqual(service.signOutCount, 1)
        XCTAssertNil(file.bytes)
    }
    func testSignOutWithoutVisibleIdentityRequiresInvitationClearBeforeRetirement() async throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile()
        let unrelated = AccountCleanupRecord(userID: UUID(), daily: .required, live: true)
        journal.records = [unrelated]
        let invitations = owner(file, journal: journal)
        invitations.receive(url())
        let original = try XCTUnwrap(file.bytes)
        let service = AccountServiceMock()
        let model = AccountModel(service: service, willDepartAccount: invitations.prepareForAccountDeparture)
        await model.start()
        service.emitState(AccountAuthState(session: nil, recovery: .init(action: .restore, storageIssue: nil)))
        for _ in 0..<100 where model.authRecovery?.action != .restore { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.authRecovery?.action, .restore)
        XCTAssertNil(model.session)
        XCTAssertNil(service.pendingDeletionUserID)

        file.rejectRemove = true
        await model.signOut()
        XCTAssertEqual(service.signOutCount, 0, "A failed unscoped clear cannot retire credentials")
        XCTAssertEqual(model.authRecovery?.action, .restore)
        XCTAssertFalse(model.isWorking)
        XCTAssertTrue(model.errorMessage?.contains("retry sign out") == true)
        XCTAssertEqual(file.bytes, original)
        XCTAssertTrue(invitations.storageFailed)
        XCTAssertEqual(journal.records, [unrelated], "An unavailable identity must not create a guessed account obligation")

        file.rejectRemove = false
        await model.signOut()
        XCTAssertEqual(service.signOutCount, 1)
        XCTAssertNil(model.authRecovery)
        XCTAssertNil(file.bytes)
        XCTAssertNil(invitations.pending)
        XCTAssertNil(owner(file).pending, "A cold owner must observe the completed clear")
        XCTAssertFalse(invitations.storageFailed)
        XCTAssertFalse(invitations.isPresented)
        XCTAssertEqual(journal.records, [unrelated])
    }
    func testStartupFailureStillCapturesAndPersistsInvitationBeforeRecovery() {
        let file = InvitationFaultFile(), invitations = owner(file)
        let startup = AppStartupModel(loadPacks: { throw DailyClassicError.missingWordPack }, invitations: invitations)
        startup.loadApp()
        invitations.receive(url())
        XCTAssertNil(startup.appModel)
        XCTAssertEqual(owner(file).pending?.code, "ABC234")
    }
    func testColdAdmissionWindowClearsNavigationAndAcknowledgesDurableToken() async throws {
        for newerArrival in [false, true] {
            let root = FileManager.default.temporaryDirectory.appending(path: "I4-death-window-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let user = UUID(), snapshot = try FriendsBetaFixtures.snapshot("successor_lobby")
            func invitationOwner() -> LiveInvitationCoordinator {
                LiveInvitationCoordinator(configuration: .init(origins: [origin]),
                    cleanupJournal: AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: root)),
                    makeStore: { PendingLiveInvitationStore(directory: root) })
            }
            let invitations = invitationOwner(); invitations.receive(url())
            let generation = try XCTUnwrap(invitations.pending?.replacementGeneration)
            let store = LiveMatchRecoveryStore(rootDirectory: root, userID: user)
            let service = CompositionLiveService(snapshot: snapshot, admitsJoin: true)
            let (first, transport) = makeLiveSessionFixture(service: service, realtime: nil, storeFactory: { _ in store })
            bindLiveAccount(first, transport: transport(user))
            first.joinMatch(code: "ABC234", invitationGeneration: generation)
            for _ in 0..<100 where first.completedInvitationGeneration == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(try store.load().completedInvitationGeneration, generation)
            XCTAssertNil(try store.load().pendingIntent)
            XCTAssertEqual(invitations.pending?.replacementGeneration, generation, "Root observation has not run: this is the death window")
            first.leaveToHome()
            let cold = invitationOwner()
            if newerArrival { cold.receive(url("DEF567")); cold.replace() }
            let (restored, nextTransport) = makeLiveSessionFixture(service: service, realtime: nil,
                storeFactory: { LiveMatchRecoveryStore(rootDirectory: root, userID: $0) })
            bindLiveAccount(restored, transport: nextTransport(user))
            XCTAssertEqual(restored.completedInvitationGeneration, generation)
            XCTAssertEqual(restored.completedInvitationAccountID, user)
            cold.bind(restored, userID: user)
            XCTAssertNil(try store.load().completedInvitationGeneration)
            XCTAssertEqual(try store.load().matchID, snapshot.match.id)
            XCTAssertEqual(cold.pending?.code, newerArrival ? "DEF567" : nil)
            XCTAssertFalse(cold.storageFailed)
            let other = UUID(); bindLiveAccount(restored, transport: nextTransport(other))
            cold.admitted(generation: generation, userID: user)
            XCTAssertFalse(cold.storageFailed)
            XCTAssertEqual(cold.pending?.code, newerArrival ? "DEF567" : nil)
            restored.leaveToHome()
        }
    }
    func testFailedCompletionAcknowledgmentRetainsDurableTokenAndRootRetryResolvesIt() async throws {
        let file = InvitationFaultFile(), invitations = owner(file), recovery = CompositionRecoveryStore(), user = UUID()
        invitations.receive(url())
        let generation = try XCTUnwrap(invitations.pending?.replacementGeneration)
        let snapshot = try FriendsBetaFixtures.snapshot("successor_lobby")
        let (session, transport) = makeLiveSessionFixture(service: CompositionLiveService(snapshot: snapshot, admitsJoin: true),
                                                         realtime: nil, storeFactory: { _ in recovery })
        bindLiveAccount(session, transport: transport(user))
        session.joinMatch(code: "ABC234", invitationGeneration: generation)
        for _ in 0..<100 where session.completedInvitationGeneration == nil { try await Task.sleep(for: .milliseconds(10)) }
        recovery.rejectWrites = true
        invitations.bind(session, userID: user)
        XCTAssertTrue(invitations.storageFailed)
        XCTAssertNil(file.bytes, "Protected navigation clear succeeded; acknowledgment alone is retryable")
        XCTAssertEqual(recovery.state.completedInvitationGeneration, generation)
        recovery.rejectWrites = false
        invitations.retry()
        XCTAssertNil(recovery.state.completedInvitationGeneration)
        XCTAssertFalse(invitations.storageFailed)
        session.leaveToHome()
    }
    func testConfiguredSharingHasManualFallbackAndNoGuessedDomain() throws {
        XCTAssertNil(LiveInvitationConfiguration(origins: []).shareURL(code: "ABC234"))
        XCTAssertEqual(LiveInvitationConfiguration(origins: [origin]).shareURL(code: "abc234"), url())
        XCTAssertNil(LiveInvitationConfiguration(origins: [URL(string: "http://invite.test")!]).shareURL(code: "ABC234"))
        XCTAssertNil(LiveInvitationConfiguration(origins: [origin]).shareURL(code: "ABCI23"))
    }
    func testJournalInvitationObligationDoesNotRemoveOtherCleanupOrLegacyRecords() throws {
        let storage = InvitationJournalFile(), user = UUID()
        storage.records = [AccountCleanupRecord(userID: user, daily: .required, live: true)]
        let journal = AccountCleanupJournal(storage: storage)
        try journal.captureInvitation(user, generation: UUID())
        try journal.completeLive(user)
        try journal.completeDaily(user)
        XCTAssertEqual(journal.invitationUsers, [user])
        XCTAssertTrue(journal.liveUsers.isEmpty)
        try journal.completeInvitation(user)
        XCTAssertTrue(storage.records.isEmpty)
    }
    func testRematchCanonicalStatesActionsAndPrivateLobbyNoSharing() throws {
        for name in ["eligible", "offered", "closed", "expired", "unavailable", "accepted", "accepted_unavailable", "moved"] {
            let snapshot = try FriendsBetaFixtures.snapshot(name)
            let actions: [LiveRematchAction] = name == "eligible" || name == "closed" ? [.offer] : []
            let presentation = try XCTUnwrap(LiveRematchPresentation.map(snapshot: snapshot, actions: actions, resolving: false))
            XCTAssertFalse(presentation.title.isEmpty)
            XCTAssertEqual(presentation.actions, actions)
            XCTAssertTrue(LiveRematchPresentation.map(snapshot: snapshot, actions: actions, resolving: true)!.actions.isEmpty)
        }
        let lobby = try FriendsBetaFixtures.snapshot("successor_lobby")
        var state = LiveMatchPresentation.State(); state.snapshot = lobby; state.phase = .ready
        let presentation = LiveMatchPresentation.map(state)
        XCTAssertFalse(presentation.permits(.copyCode))
        XCTAssertFalse(presentation.permits(.shareCode))
        let missing = LiveMatchSnapshot(serverTime: lobby.serverTime, match: lobby.match,
                                        members: lobby.members.filter(\.isSelf), round: lobby.round, selection: lobby.selection)
        state.snapshot = missing
        XCTAssertEqual(LiveMatchPresentation.map(state).notice?.title, "Rematch player unavailable")
    }
    func testProtocolNoticeRetainsIntentAndExplicitRetry() {
        var state = LiveMatchPresentation.State(); state.serviceNeedsUpdate = true
        state.pendingIntent = .create(requestID: UUID(), roundCount: 3, clientBuild: 3)
        let presentation = LiveMatchPresentation.map(state)
        XCTAssertEqual(presentation.notice?.title, "Live service needs an update")
        XCTAssertEqual(presentation.notice?.controls.map(\.action), [.retry, .discardCreate])
        XCTAssertFalse(presentation.permits(.create))
    }

    func testProfileReturnConfirmationUnresolvedIntentAndNewArrivalFenceConsent() async throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url())
        let service = AccountServiceMock(), user = UUID(), liveService = CompositionLiveService()
        let root = FileManager.default.temporaryDirectory.appending(path: "I4-confirm-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = CompositionRecoveryStore()
        let app = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main), guestStore: DailyClassicStore(directory: root),
            accountService: nil, accountModelService: service,
            liveTransportFactory: { LiveAccountTransport(userID: $0, service: liveService, realtime: nil,
                                                        refresh: { _ in false }, isValid: { true }) },
            liveStoreFactory: { _ in recovery }, cleanupJournal: invitations.cleanupJournal)
        app.invitations = invitations
        await app.start()
        XCTAssertNil(invitations.confirmation(for: app))
        XCTAssertNil(app.live.pendingIntent)
        service.loadedProfile = PlayerProfile(userID: user, displayName: "Player", avatarSeed: "seed", setupCompleted: false,
                                              createdAt: Date(), updatedAt: Date())
        service.emit(AccountSession(userID: user, expiresAt: .distantFuture))
        for _ in 0..<100 where app.account.profile == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(invitations.confirmation(for: app), "Profile setup is required before explicit consent")
        service.updatedProfile = profile(user)
        await app.account.saveProfile()
        let confirmed = try XCTUnwrap(invitations.confirmation(for: app))
        XCTAssertEqual(confirmed.userID, user)
        XCTAssertNil(app.live.pendingIntent, "Sign in/profile return never joins")
        let cold = owner(file, journal: InvitationJournalFile())
        cold.bind(app.live, userID: user)
        XCTAssertNil(app.live.pendingIntent, "Relaunch/restore never joins")
        invitations.receive(url("DEF567")); invitations.replace()
        XCTAssertFalse(invitations.join(confirmed, app: app), "A newer saved generation needs new consent")
        let newer = try XCTUnwrap(invitations.confirmation(for: app))
        XCTAssertTrue(invitations.join(newer, app: app))
        XCTAssertNil(invitations.confirmation(for: app), "An unresolved Join cannot be replaced")
        guard case .join(let command, _, _, let generation) = app.live.pendingIntent else { return XCTFail("durable Join") }
        XCTAssertEqual(command.code, "DEF567")
        XCTAssertEqual(generation, newer.invitation.replacementGeneration)
        app.live.leaveToHome()
    }
    func testCanonicalAdmissionClearFailureRemainsActionableAcrossRelaunch() throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile(), invitations = owner(file, journal: journal)
        invitations.receive(url())
        let generation = try XCTUnwrap(invitations.pending?.replacementGeneration)
        file.rejectRemove = true
        invitations.admitted(generation: generation, userID: UUID())
        XCTAssertTrue(invitations.storageFailed)
        let cold = owner(file, journal: journal)
        XCTAssertNil(cold.visiblePending)
        file.rejectRemove = false
        cold.retry()
        XCTAssertNil(cold.pending)
        XCTAssertFalse(cold.cleanupBlocked)
    }
    func testFailedInvitationJournalCannotCreateUncapturedDeletionRecovery() async throws {
        let file = InvitationFaultFile(), journal = InvitationJournalFile(), invitations = owner(file, journal: journal)
        invitations.receive(url())
        let service = AccountServiceMock(), user = UUID()
        service.restoredSession = AccountSession(userID: user, expiresAt: .distantFuture)
        service.loadedProfile = profile(user)
        let account = AccountModel(service: service, willDepartAccount: invitations.prepareForAccountDeparture)
        await account.start()
        journal.rejectWrite = true
        await account.deleteAccount()
        XCTAssertEqual(service.deleteCount, 0)
        XCTAssertEqual(account.session?.userID, user)
        XCTAssertNil(account.authRecovery, "No deletion was captured or dispatched")
    }
    func testRestoredInvitationFencesExplicitLiveEntryEvenAfterResumeReenablesFollowing() async throws {
        let file = InvitationFaultFile(), invitations = owner(file), recovery = CompositionRecoveryStore()
        let snapshot = try FriendsBetaFixtures.snapshot("eligible"), user = UUID()
        recovery.state.matchID = snapshot.match.id
        let (session, transport) = makeLiveSessionFixture(service: CompositionLiveService(snapshot: snapshot), realtime: nil,
                                                         storeFactory: { _ in recovery })
        bindLiveAccount(session, transport: transport(user))
        invitations.receive(url()); invitations.bind(session, userID: user)
        let cold = owner(file); cold.bind(session, userID: user)
        XCTAssertFalse(recovery.state.successorFollowAllowed)
        session.resumeSavedMatch()
        cold.fenceForLiveEntry()
        XCTAssertFalse(recovery.state.successorFollowAllowed, "Restored navigation fences the actual Live entry")
        XCTAssertNil(session.pendingIntent)
        session.leaveToHome()
    }
    func testStoredOriginFromAnotherBuildCannotBecomeJoinConsent() {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url())
        let other = LiveInvitationCoordinator(configuration: .init(origins: []), cleanupJournal: invitations.cleanupJournal,
                                               makeStore: { PendingLiveInvitationStore(persistence: file) })
        XCTAssertNotNil(other.pending)
        XCTAssertNil(other.visiblePending)
        XCTAssertTrue(other.configurationRejectsPending)
    }
    func testExplicitDeletionClearsInvitationWhileIdentitySwitchOnlyFencesIt() async throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url())
        let service = AccountServiceMock(), user = UUID(), other = UUID()
        service.restoredSession = AccountSession(userID: user, expiresAt: .distantFuture)
        service.loadedProfile = profile(user)
        let model = AccountModel(service: service, willDepartAccount: invitations.prepareForAccountDeparture)
        await model.start()
        let original = file.bytes
        service.emit(AccountSession(userID: other, expiresAt: .distantFuture))
        await Task.yield()
        XCTAssertEqual(file.bytes, original, "An account switch keeps only unconfirmed navigation")
        await model.deleteAccount()
        XCTAssertEqual(service.deleteCount, 1)
        XCTAssertNil(file.bytes)
        XCTAssertNil(owner(file).pending)
    }

    func testActualInvitationAndRematchLayoutsAtCompactAndAccessibilitySizes() async throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url())
        for accessibility in [false, true] {
            try await capture(LiveInvitationView(invitations: invitations, app: nil, resolveRace: {}, joined: {}),
                              name: "invitation-startup", accessibility: accessibility, actions: .hostedViewport(expectedButtons: ["Keep invitation", "Discard invitation"]))
            invitations.receive(url("DEF567"))
            try await capture(LiveInvitationView(invitations: invitations, app: nil, resolveRace: {}, joined: {}),
                              name: "invitation-replacement", accessibility: accessibility, actions: .hostedViewport(expectedButtons: ["Keep current", "Replace invitation"]))
            invitations.keepCurrent()
            for name in ["eligible", "offered", "incoming", "closed", "expired", "unavailable", "accepted", "accepted_unavailable"] {
                let original = try FriendsBetaFixtures.snapshot(name == "incoming" ? "offered" : name)
                let snapshot = name == "incoming" ? LiveMatchSnapshot(serverTime: original.serverTime, match: original.match,
                    members: original.members.map { LiveMatchMember(id: $0.id, seat: $0.seat, displayName: $0.displayName,
                        avatarSeed: $0.avatarSeed, isSelf: !$0.isSelf, isDeleted: $0.isDeleted) }, round: original.round,
                    revision: original.revision, revealedRounds: original.revealedRounds, standings: original.standings,
                    selection: original.selection, rematch: original.rematch) : original
                let recovery = CompositionRecoveryStore(); recovery.state.matchID = snapshot.match.id
                let service = CompositionLiveService(snapshot: snapshot)
                let (session, transport) = makeLiveSessionFixture(service: service, realtime: nil, storeFactory: { _ in recovery })
                bindLiveAccount(session, transport: transport(UUID()))
                session.resumeSavedMatch()
                for _ in 0..<100 where session.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
                let buttons = session.availableRematchActions.map { LiveRematchPresentation.title($0, state: snapshot.rematch!.state) }
                if name == "incoming" { XCTAssertEqual(buttons, ["Accept rematch", "Decline"]) }
                try await capture(ScrollView { LiveRematchView(session: session, snapshot: snapshot).padding(16) }
                    .background(Color.page), name: "rematch-\(name)", accessibility: accessibility, actions: .hostedViewport(expectedButtons: buttons))
                session.leaveToHome()
            }
            let root = FileManager.default.temporaryDirectory.appending(path: "I4-render-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let account = AccountServiceMock(), user = UUID(), liveStore = CompositionRecoveryStore()
            let app = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
                guestStore: DailyClassicStore(directory: root), accountService: nil, accountModelService: account,
                liveTransportFactory: { LiveAccountTransport(userID: $0, service: CompositionLiveService(), realtime: nil,
                                                            refresh: { _ in false }, isValid: { true }) },
                liveStoreFactory: { _ in liveStore }, cleanupJournal: invitations.cleanupJournal)
            app.invitations = invitations
            await app.start()
            try await capture(LiveInvitationView(invitations: invitations, app: app, resolveRace: {}, joined: {}),
                              name: "invitation-signed-out", accessibility: accessibility,
                              actions: .hostedViewport(expectedButtons: ["Open Account", "Keep invitation", "Discard invitation"]))
            account.loadedProfile = profile(user); account.emit(AccountSession(userID: user, expiresAt: .distantFuture))
            for _ in 0..<100 where app.account.profile == nil { try await Task.sleep(for: .milliseconds(10)) }
            try await capture(LiveInvitationView(invitations: invitations, app: app, resolveRace: {}, joined: {}),
                              name: "invitation-confirm-current-account", accessibility: accessibility,
                              actions: .hostedViewport(expectedButtons: ["Join ABC234", "Keep invitation", "Discard invitation"]))
            app.live.createMatch()
            for _ in 0..<100 where app.live.isCommandInFlight { try await Task.sleep(for: .milliseconds(10)) }
            try await capture(LiveInvitationView(invitations: invitations, app: app, resolveRace: {}, joined: {}),
                              name: "invitation-unresolved-race", accessibility: accessibility,
                              actions: .hostedViewport(expectedButtons: ["Resolve saved race", "Keep invitation", "Discard invitation"]))
            app.live.leaveToHome()
            let predecessor = try FriendsBetaFixtures.snapshot("accepted_selected_elsewhere")
            let successor = try FriendsBetaFixtures.snapshot("successor_lobby")
            let recovery = CompositionRecoveryStore(); recovery.state.matchID = predecessor.match.id
            let (session, transport) = makeLiveSessionFixture(service: CompositionLiveService(snapshot: predecessor, successor: successor),
                                                              realtime: nil, storeFactory: { _ in recovery })
            bindLiveAccount(session, transport: transport(UUID()))
            session.resumeSavedMatch()
            for _ in 0..<100 where session.resumeConfirmationTarget == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(session.resumeConfirmationTarget?.match.id, successor.match.id)
            try await capture(NavigationStack { LiveMatchFlowView(session: session, hapticsEnabled: false, highContrast: accessibility,
                                                                accountName: "Player") }, name: "resume-actual-successor", accessibility: accessibility,
                                   actions: .hostedViewport(expectedButtons: ["Switch race and resume", "Cancel"]))
            session.leaveToHome()
        }
    }
    func testCurrentCompletedFlowRendersStandingsHistoryAndRematchActions() async throws {
        for accessibility in [false, true] {
            for name in ["eligible", "offered", "incoming", "closed", "expired", "unavailable", "3-round-3-reveal", "5-round-5-reveal"] {
                let original: LiveMatchSnapshot
                if name.contains("round-") {
                    var data = try Phase4LiveFixtures.object(name)
                    var rematch = try XCTUnwrap(data["rematch"] as? [String: Any])
                    rematch["is_eligible"] = true
                    rematch["reason"] = NSNull()
                    if name.hasPrefix("5-") {
                        let members = try XCTUnwrap(data["members"] as? [[String: Any]])
                        let member = try XCTUnwrap(members.first(where: { ($0["is_self"] as? Bool) == false }))
                        let opponent = try XCTUnwrap(member["id"] as? String)
                        rematch["state"] = "offered"
                        rematch["initiator_member_id"] = opponent
                        rematch["consenting_member_ids"] = [opponent]
                    } else { rematch["state"] = "eligible" }
                    data["rematch"] = rematch
                    original = try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(data))
                } else { original = try FriendsBetaFixtures.snapshot(name == "incoming" ? "offered" : name) }
                let snapshot = name == "incoming" ? LiveMatchSnapshot(serverTime: original.serverTime, match: original.match,
                    members: original.members.map { LiveMatchMember(id: $0.id, seat: $0.seat, displayName: $0.displayName,
                        avatarSeed: $0.avatarSeed, isSelf: !$0.isSelf, isDeleted: $0.isDeleted) }, round: original.round,
                    revision: original.revision, revealedRounds: original.revealedRounds, standings: original.standings,
                    selection: original.selection, rematch: original.rematch) : original
                XCTAssertNotNil(snapshot.standings)
                XCTAssertNotNil(snapshot.rematch, "Current completed projections include canonical rematch state")
                let recovery = CompositionRecoveryStore(); recovery.state.matchID = snapshot.match.id
                let (session, transport) = makeLiveSessionFixture(service: CompositionLiveService(snapshot: snapshot), realtime: nil,
                                                                 storeFactory: { _ in recovery })
                bindLiveAccount(session, transport: transport(UUID()))
                session.resumeSavedMatch()
                for _ in 0..<100 where session.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
                let actions = session.availableRematchActions.map { LiveRematchPresentation.title($0, state: snapshot.rematch!.state) }
                let history = snapshot.revealedRounds.count > 1 ? snapshot.revealedRounds.map { "Round \($0.number)" } : []
                try await capture(NavigationStack {
                    LiveMatchFlowView(session: session, hapticsEnabled: false, highContrast: accessibility, accountName: "Player")
                }, name: "completed-flow-\(name)", accessibility: accessibility,
                    actions: .hostedViewport(expectedButtons: actions + history + ["Home"]))
                session.leaveToHome()
            }
        }
    }

    func testActualRootInvitationBannerKeepsA44PointTarget() async throws {
        let file = InvitationFaultFile(), invitations = owner(file)
        invitations.receive(url()); invitations.isPresented = false
        let root = FileManager.default.temporaryDirectory.appending(path: "I4-banner-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main), tutorialPack: WordPack.load(bundle: .main),
                                             guestStore: DailyClassicStore(directory: root), accountService: nil,
                                             cleanupJournal: invitations.cleanupJournal)
        app.invitations = invitations
        for accessibility in [false, true] {
            try await capture(DailyAppView(app: app, invitations: invitations), name: "root-invitation-banner",
                              accessibility: accessibility, actions: .safeScreen(expectedButtons: ["Open invitation ABC234"]))
        }
    }
    func testMalformedInvitationCleanupJournalFailsClosedAndPreservesBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "I4-journal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = AccountCleanupJournalFile(directory: root)
        let record = AccountCleanupRecord(userID: UUID(), daily: nil, live: false,
                                          invitationClearRequired: true,
                                          invitationGeneration: PendingLiveInvitation.unassignedGeneration)
        try file.save([record])
        let original = try Data(contentsOf: file.url)
        let journal = AccountCleanupJournal(storage: file)
        XCTAssertTrue(journal.isUnavailable)
        XCTAssertThrowsError(try journal.reload())
        XCTAssertEqual(try Data(contentsOf: file.url), original)
    }
    private enum CaptureActions {
        case hostedViewport(expectedButtons: [String])
        case safeScreen(expectedButtons: [String])

        var expectedButtons: [String] {
            switch self {
            case .hostedViewport(let expectedButtons), .safeScreen(let expectedButtons):
                return expectedButtons
            }
        }

        @MainActor
        func viewport(in hosted: GameplayContainmentHost) -> CGRect {
            switch self {
            case .hostedViewport:
                return hosted.viewport
            case .safeScreen:
                return hosted.window.convert(hosted.window.bounds.inset(by: hosted.window.safeAreaInsets), to: nil)
            }
        }

        func includes(label: String) -> Bool {
            switch self {
            case .hostedViewport:
                return true
            case .safeScreen(let expectedButtons):
                return expectedButtons.contains(label)
            }
        }
    }

    private func capture<V: View>(_ view: V, name: String, accessibility: Bool,
                                 actions: CaptureActions = .hostedViewport(expectedButtons: [])) async throws {
        try await GameplayContainmentHost.withHost(view, landscape: false, accessibility: accessibility) { hosted in
            hosted.window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
            try await hosted.settle()
            let renderer = UIGraphicsImageRenderer(bounds: hosted.window.bounds)
            let image = renderer.image { _ in hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "I4-\(name)-\(accessibility ? "AX5" : "compact")"
            attachment.lifetime = .keepAlways; add(attachment)
            let viewport = actions.viewport(in: hosted)
            var reached = Set<String>()
            @MainActor func observe() {
                let elements = hosted.elements()
                XCTAssertFalse(elements.isEmpty, "Actual native accessibility tree must render")
                for element in elements where element.button && element.frame.intersects(viewport) {
                    if !actions.includes(label: element.label) { continue }
                    XCTAssertGreaterThanOrEqual(element.frame.height, 43, "\(name): \(element.label)")
                    let visible = element.clips.reduce(element.frame.intersection(viewport)) { $0.intersection($1) }
                    if visible.height >= min(43, element.frame.height), visible.width >= min(43, element.frame.width) {
                        reached.insert(element.label)
                    }
                }
            }
            observe()
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
            let scrolls = descendants(hosted.host.view).compactMap { $0 as? UIScrollView }
            let horizontal = scrolls.filter { $0.contentSize.width > $0.bounds.width + 1 }
            @MainActor func observeHorizontalActions() {
                observe()
                for scroll in horizontal {
                    let original = scroll.contentOffset
                    let maxX = scroll.contentSize.width - scroll.bounds.width
                    for x in stride(from: CGFloat(0), through: maxX, by: max(1, scroll.bounds.width * 0.6)) {
                        scroll.setContentOffset(CGPoint(x: x, y: original.y), animated: false)
                        hosted.host.view.layoutIfNeeded(); observe()
                    }
                    scroll.setContentOffset(CGPoint(x: maxX, y: original.y), animated: false)
                    hosted.host.view.layoutIfNeeded(); observe()
                    scroll.setContentOffset(original, animated: false)
                }
            }
            for scroll in scrolls where scroll.contentSize.height > scroll.bounds.height {
                let maxOffset = scroll.contentSize.height - scroll.bounds.height
                for offset in stride(from: CGFloat(0), through: maxOffset, by: max(1, viewport.height * 0.6)) {
                    scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                    hosted.host.view.layoutIfNeeded(); observeHorizontalActions()
                }
                if name.hasPrefix("completed-flow-") {
                    scroll.setContentOffset(CGPoint(x: 0, y: maxOffset / 2), animated: false)
                    hosted.host.view.layoutIfNeeded()
                    let middle = renderer.image { _ in hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true) }
                    let attachment = XCTAttachment(image: middle); attachment.name = "I4-\(name)-middle"; attachment.lifetime = .keepAlways; add(attachment)
                }
                scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
                hosted.host.view.layoutIfNeeded(); observeHorizontalActions()
                let bottom = renderer.image { _ in hosted.window.drawHierarchy(in: hosted.window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: bottom); attachment.name = "I4-\(name)-bottom"; attachment.lifetime = .keepAlways; add(attachment)
            }
            for button in actions.expectedButtons {
                XCTAssertTrue(reached.contains(button), "\(name): \(button) must be scroll-reachable")
            }
        }
    }

    private func profile(_ user: UUID) -> PlayerProfile {
        PlayerProfile(userID: user, displayName: "Player", avatarSeed: "seed", setupCompleted: true,
                      createdAt: Date(), updatedAt: Date())
    }
}

private final class InvitationFaultFile: PendingLiveInvitationPersistence, @unchecked Sendable {
    var bytes: Data?
    var rejectRead = false, rejectWrite = false, rejectRemove = false
    func read() throws -> Data? { if rejectRead { throw Failure.unavailable }; return bytes }
    func write(_ data: Data) throws { if rejectWrite { throw Failure.unavailable }; bytes = data }
    func remove() throws { if rejectRemove { throw Failure.unavailable }; bytes = nil }
    enum Failure: Error { case unavailable }
}
private final class InvitationJournalFile: AccountCleanupJournalStoring {
    var records: [AccountCleanupRecord] = []
    var rejectWrite = false
    func load() throws -> [AccountCleanupRecord] { records }
    func save(_ records: [AccountCleanupRecord]) throws {
        if rejectWrite { throw InvitationFaultFile.Failure.unavailable }; self.records = records
    }
}

private final class CompositionRecoveryStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    var state = LiveRecoveryState()
    var rejectWrites = false
    func load() throws -> LiveRecoveryState { state }
    func save(_ state: LiveRecoveryState) throws {
        if rejectWrites { throw InvitationFaultFile.Failure.unavailable }; self.state = state
    }
    func clear() throws { state = LiveRecoveryState() }
}
private struct CompositionLiveService: LiveMatchServicing {
    var snapshot: LiveMatchSnapshot? = nil
    var successor: LiveMatchSnapshot? = nil
    var admitsJoin = false
    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func joinMatch(_ command: LiveJoinCommand) async throws -> UUID {
        if admitsJoin, let snapshot { return snapshot.match.id }
        throw LiveMatchServiceError.unavailable
    }
    func rematch(_ command: LiveRematchCommand) async throws -> LiveRematchReceipt { throw LiveMatchServiceError.unavailable }
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String, clientBuild: Int) async throws -> LiveGuessReceipt { throw LiveMatchServiceError.unavailable }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot {
        if let successor, successor.match.id == matchID { return successor }
        guard let snapshot else { throw LiveMatchServiceError.unavailable }; return snapshot
    }
}
