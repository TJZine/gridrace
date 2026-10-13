import Foundation
import XCTest
@testable import GridRace

@MainActor
final class LiveMatchIntegrationTests: XCTestCase {
    func testTwoClientProcess() async throws {
        var environment = ProcessInfo.processInfo.environment
        let admission = try LocalIntegrationAdmission.admit(environment: environment, purpose: .live)
        if environment["GRIDRACE_LIVE_WAIT_FOR_CODE"] == "1" {
            let coordinationID = try XCTUnwrap(UUID(uuidString: environment["GRIDRACE_LIVE_COORDINATION_ID"] ?? ""))
            let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            let directory = support.appending(path: "GridRaceIntegration/Coordination/\(coordinationID.uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("ready".utf8).write(to: directory.appending(path: "ready"), options: [.atomic, .completeFileProtection])
            print("BARRIER native guest admitted and ready before host domain work")
            let codeFile = directory.appending(path: "public-code.json")
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while !FileManager.default.fileExists(atPath: codeFile.path) {
                guard ContinuousClock.now < deadline else { throw IntegrationFailure.timeout }
                try await Task.sleep(for: .milliseconds(100))
            }
            let payload = try JSONDecoder().decode(PublicFixtureCode.self, from: Data(contentsOf: codeFile))
            let code = try XCTUnwrap(LiveInvitationParser.canonicalCode(payload.code))
            environment["GRIDRACE_LIVE_JOIN_CODE"] = code
        }
        if environment["GRIDRACE_LIVE_WAIT_FOR_SELECTION"] == "1" {
            let coordinationID = try XCTUnwrap(UUID(uuidString: environment["GRIDRACE_SELECTION_COORDINATION_ID"] ?? ""))
            let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            let directory = support.appending(path: "GridRaceIntegration/Coordination/\(coordinationID.uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("ready".utf8).write(to: directory.appending(path: "ready"), options: [.atomic, .completeFileProtection])
            print("BARRIER third native process admitted and ready before selection reads")
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while !FileManager.default.fileExists(atPath: directory.appending(path: "select-now").path) {
                guard ContinuousClock.now < deadline else { throw IntegrationFailure.timeout }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let role = try XCTUnwrap(environment["GRIDRACE_LIVE_ROLE"])
        let scenario = try XCTUnwrap(environment["GRIDRACE_LIVE_SCENARIO"])
        let failedGuess = try XCTUnwrap(environment["GRIDRACE_LIVE_FAILED_GUESS"])
        let count = try XCTUnwrap(Int(environment["GRIDRACE_LIVE_ROUND_COUNT"] ?? ""))
        let target = try XCTUnwrap(Int(environment["GRIDRACE_LIVE_ROUND_NUMBER"] ?? ""))
        // The host app restores its own account while XCTest runs. Keep this
        // simulated device's real Keychain credentials separate from the app,
        // with the same namespace on every process relaunch of this fixture.
        let credentialNamespace = "GridRaceLiveIntegration.\(admission.receipt.runID.uuidString).\(admission.receipt.userID.uuidString)"
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let invitationRoot = support.appending(path: "GridRaceIntegration/invitation-\(admission.receipt.runID)")
        func invitationOwner() -> LiveInvitationCoordinator {
            LiveInvitationCoordinator(configuration: .init(origins: [URL(string: "https://invite.test")!]),
                cleanupJournal: AccountCleanupJournal(storage: AccountCleanupJournalFile(directory: invitationRoot)),
                makeStore: { PendingLiveInvitationStore(directory: invitationRoot) })
        }
        var invitations = invitationOwner()
        if scenario == "friends", role == "guest" {
            invitations.receive(try XCTUnwrap(URL(string: "https://invite.test/join/\(environment["GRIDRACE_LIVE_JOIN_CODE"] ?? "")")))
            let pending = try XCTUnwrap(invitations.pending)
            invitations = invitationOwner() // Cold navigation restore before authentication.
            XCTAssertEqual(invitations.pending, pending)
            XCTAssertNil(LiveMatchSession().savedMatchID)
            print("PASS live client signed-out invitation protected navigation restore")
        }
        let account = SupabaseAccountService(configuration: admission.configuration,
            storage: SecureAuthStorage(service: credentialNamespace))
        if role == "invitation-root" {
            try await runInvitationRoot(admission: admission, environment: environment,
                account: account, invitations: invitations, makeInvitations: invitationOwner,
                root: invitationRoot)
            return
        }
        let signedIn = try await account.signInForLocalTesting(
            email: admission.email, password: admission.password)
        try admission.validateIdentity(signedIn.userID)
        if scenario == "friends", role == "guest" {
            let model = AccountModel(service: account)
            await model.start()
            try await eventually("real profile load") { model.profile != nil }
            XCTAssertNotNil(invitations.pending, "Profile setup cannot consume navigation")
            XCTAssertTrue(model.needsProfileSetup, "The fresh Auth fixture must exercise profile setup")
            model.displayNameDraft = "Proof guest"
            await model.saveProfile()
            XCTAssertFalse(model.needsProfileSetup)
            XCTAssertNotNil(invitationOwner().pending)
            print("PASS live client real Auth profile return retains invitation")
        }
        let store = try LiveMatchRecoveryStore.applicationSupport(userID: signedIn.userID)
        if ["friends-stale", "friends-select", "friends-race"].contains(role) {
            let predecessor = try XCTUnwrap(UUID(uuidString: environment["GRIDRACE_LIVE_MATCH_ID"] ?? ""))
            try store.save(LiveRecoveryState(matchID: predecessor, pendingIntent: nil))
        }
        let bound = try account.makeLiveTransport(userID: signedIn.userID)
        let service = MeasuredLiveMatchService(
            bound.service, injectLoss: scenario == "product" && role != "resume",
            target: target, waitForAdvance: role == "advance-guest", friends: scenario == "friends", selectionBarrier: role == "friends-race", closureBarrier: role == "friends-close-disabled"
        )
        if role == "friends-signal-host" || role == "friends-signal-guest" {
            try await runRematchSignalRole(role, service: service,
                realtime: try XCTUnwrap(bound.realtime),
                predecessor: try XCTUnwrap(UUID(uuidString: environment["GRIDRACE_LIVE_MATCH_ID"] ?? "")))
            return
        }
        let realtime: (any LiveMatchRealtimeServicing)? =
            environment["GRIDRACE_LIVE_DISABLE_REALTIME"] == "1"
            ? nil
            : FaultedRealtimeService(base: try XCTUnwrap(bound.realtime))
        let productionTiming = LiveMatchSessionTiming.production
        let timing = role == "friends-race"
            ? LiveMatchSessionTiming(requestTimeout: .seconds(120), staleAfter: productionTiming.staleAfter,
                                     retryBackoff: productionTiming.retryBackoff)
            : productionTiming
        let session = LiveMatchSession(timing: timing)
        let transport = LiveAccountTransport(userID: bound.userID, service: service, realtime: realtime,
            refresh: bound.refresh, isValid: bound.isValid)
        session.changeAccount(to: signedIn.userID, transport: transport)
        if session.pendingIntent != nil { XCTAssertTrue(session.isInputLocked) }
        if scenario == "friends" {
            invitations.bind(session, userID: signedIn.userID)
            if role.hasPrefix("friends-") {
                try await runFriendsRole(role, session: session, service: service, store: store,
                    predecessor: try XCTUnwrap(UUID(uuidString: environment["GRIDRACE_LIVE_MATCH_ID"] ?? "")), count: count)
                return
            }
        }

        if role == "host" {
            session.createMatch(roundCount: count)
            try await eventually("host create") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.phase == .ready && session.snapshot?.members.isEmpty == false
            }
            XCTAssertEqual(session.snapshot?.match.roundCount, count)
            try await eventually("guest roster") { session.snapshot?.members.count == 2 }
        } else if role == "guest" {
            session.joinMatch(code: try XCTUnwrap(environment["GRIDRACE_LIVE_JOIN_CODE"]),
                              invitationGeneration: scenario == "friends" ? invitations.pending?.replacementGeneration : nil)
            if scenario == "friends" {
                try await eventually("current service update fence") { session.serviceNeedsUpdate }
                let original = session.pendingIntent
                let before = await service.metrics().requests
                try await Task.sleep(for: .milliseconds(500))
                let after = await service.metrics().requests
                XCTAssertEqual(after, before, "No automatic mismatch retry")
                XCTAssertEqual(session.pendingIntent, original)
                XCTAssertNil(session.savedMatchID, "Unconfirmed admission cannot replace pointer")
                session.retry()
            }
            try await eventually("guest roster") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.phase == .ready && session.snapshot?.members.count == 2
            }
        } else {
            let expected = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(
                environment["GRIDRACE_LIVE_MATCH_ID"]
            )))
            XCTAssertTrue(session.savedMatchID == expected, "relaunch must restore its own container")
            session.resumeSavedMatch()
            try await eventually("relaunch canonical state") {
                session.snapshot != nil && session.pendingIntent == nil
            }
            if role == "resume" || role == "survivor" {
                try await assertReveal(session, count: count, target: target,
                                       incomplete: role == "survivor" && target < count)
                session.leaveToHome()
                print("PASS live client canonical relaunch \(role) count \(count) round \(target)")
                return
            }
            XCTAssertTrue(["advance-host", "advance-guest", "solve-host", "solve-guest"].contains(role))
            // A delayed old receipt may finish after the creator's next Start.
            XCTAssertTrue([target - 1, target].contains(session.snapshot?.round.number ?? 0))
            XCTAssertEqual(session.snapshot?.revealedRounds.count, target - 1)
            XCTAssertTrue(session.pendingIntent == nil)
            XCTAssertTrue(session.guessDraft.isEmpty)
        }

        let matchID = try XCTUnwrap(session.savedMatchID)
        if role == "guest" || role == "advance-guest" || role == "solve-guest" {
            do {
                _ = try await service.startMatch(id: matchID, roundNumber: target)
                XCTFail("guest advancement must be denied")
            } catch LiveMatchServiceError.server(.notHost) {
                print("PASS live client guest advancement denied")
            }
        } else if role != "solve-host" {
            session.startMatch()
        }
        try await eventually("configured countdown/play") {
            if session.canRetry && session.hasPendingStart { session.retry() }
            return !session.hasPendingStart && session.snapshot?.round.number == target && session.snapshot?.round.state == .playing
        }
        XCTAssertEqual(session.snapshot?.match.roundCount, count)
        XCTAssertTrue(session.snapshot?.round.answer == nil)
        XCTAssertEqual(session.snapshot?.revealedRounds.count, target - 1)
        XCTAssertTrue(session.snapshot?.round.players.filter {
            $0.memberID != session.snapshot?.members.first(where: \.isSelf)?.id
        }.allSatisfy { $0.board == nil && $0.solveDurationMilliseconds == nil } == true)
        XCTAssertTrue(session.pendingIntent == nil)
        XCTAssertTrue(session.guessDraft.isEmpty)
        XCTAssertEqual(selfPlayer(in: session.snapshot)?.acceptedGuessCount, 0)
        XCTAssertTrue(selfPlayer(in: session.snapshot)?.board?.isEmpty == true)
        let canonicalHistory = session.snapshot?.revealedRounds
        session.backgrounded()
        session.foregrounded()
        session.leaveToHome()
        XCTAssertTrue(session.snapshot == nil)
        session.resumeSavedMatch()
        try await eventually("Home/background/Resume") {
            session.snapshot?.round.number == target && session.snapshot?.round.state == .playing
        }
        XCTAssertTrue(session.snapshot?.revealedRounds == canonicalHistory)
        if scenario == "product" || scenario == "friends" || role.hasPrefix("solve-") {
            let testGuess = environment["GRIDRACE_LIVE_TEST_GUESS"] ?? failedGuess
            try await finishRound(session, guess: testGuess, solved: testGuess != failedGuess)
            try await assertReveal(session, count: count, target: target)
            try await service.assertReceiptReplay(matchID: matchID)
            if scenario == "mixed" {
                let standings = try XCTUnwrap(session.snapshot?.standings)
                let ownID = try XCTUnwrap(session.snapshot?.members.first(where: \.isSelf)?.id)
                let own = try XCTUnwrap(standings.players.first { $0.memberID == ownID })
                let solved = role == "solve-host"
                XCTAssertEqual(own.roundsSolved, solved ? target : 0)
                XCTAssertEqual(own.efficiencyPoints, solved ? target * 6 : 0)
                XCTAssertEqual(own.placement, solved ? 1 : 2)
            }
            let revealed = try XCTUnwrap(session.snapshot)
            if role == "host" || role == "advance-host" || role == "solve-host" {
                // Real duplicate and stale requests retain the original target.
                async let first = service.startMatch(id: matchID, roundNumber: target)
                async let second = service.startMatch(id: matchID, roundNumber: target)
                _ = try await (first, second)
                let after = try await service.snapshot(matchID: matchID)
                XCTAssertEqual(after.match.currentRound, target)
                XCTAssertEqual(after.revision, revealed.revision)
            }
        }
        session.leaveToHome()
        if scenario == "product" {
            // Recreate an accepted response lost at process death, using only this
            // client's real original request and its existing protected recovery file.
            let pending = try await service.acceptedIntent(matchID: matchID)
            let store = try LiveMatchRecoveryStore.applicationSupport(userID: signedIn.userID)
            try store.save(LiveRecoveryState(matchID: matchID, pendingIntent: pending))
            print("INJECTION persisted real accepted old-round request for separate-process relaunch")
        }

        if scenario == "friends", role == "guest" {
            XCTAssertNotNil(session.completedInvitationGeneration, "Admission marker survives root clear crash window")
            XCTAssertNotNil(invitationOwner().pending)
        }
        let metrics = await service.metrics()
        XCTAssertGreaterThan(metrics.requests, 0)
        XCTAssertLessThan(metrics.maximumLatencyMilliseconds, 10_000)
        print(
            "PASS live client \(role) \(scenario) \(metrics.requests) requests "
                + "\(metrics.maximumLatencyMilliseconds)ms max"
        )
    }

    private func runInvitationRoot(
        admission: LocalIntegrationAdmission, environment: [String: String],
        account: SupabaseAccountService, invitations: LiveInvitationCoordinator,
        makeInvitations: () -> LiveInvitationCoordinator, root: URL
    ) async throws {
        let code = try XCTUnwrap(environment["GRIDRACE_LIVE_JOIN_CODE"])
        let origin = "https://invite.test/join/"
        invitations.receive(try XCTUnwrap(URL(string: origin + code)))
        let original = try XCTUnwrap(invitations.pending)
        let coldArrival = makeInvitations()
        XCTAssertEqual(coldArrival.pending, original)
        var measured: MeasuredLiveMatchService?
        let joinTrace = IntegrationJoinTrace()
        let app = try DailyAccountCoordinator(dailyPack: DailyWordPack.load(bundle: .main),
            tutorialPack: WordPack.load(bundle: .main),
            guestStore: DailyClassicStore(directory: root.appending(path: "guest")),
            accountService: account,
            liveTransportFactory: { user in
                let bound = try account.makeLiveTransport(userID: user)
                let service = MeasuredLiveMatchService(bound.service, injectLoss: false,
                    target: 1, waitForAdvance: false, friends: true, joinTrace: joinTrace)
                measured = service
                return LiveAccountTransport(userID: user, service: service, realtime: bound.realtime,
                    refresh: bound.refresh, isValid: bound.isValid)
            },
            liveStoreFactory: { LiveMatchRecoveryStore(rootDirectory: root, userID: $0) },
            cleanupJournal: coldArrival.cleanupJournal)
        app.invitations = coldArrival
        await app.start()
        XCTAssertNil(app.account.session)
        XCTAssertTrue(app.isDailyPlayable)
        XCTAssertNil(coldArrival.confirmation(for: app))
        XCTAssertNil(app.live.pendingIntent)
        await app.account.signInForLocalTesting(email: admission.email, password: admission.password)
        try await eventually("root actual profile return") { app.account.profile != nil }
        try admission.validateIdentity(try XCTUnwrap(app.account.session?.userID))
        XCTAssertTrue(app.account.needsProfileSetup)
        XCTAssertNil(coldArrival.confirmation(for: app))
        XCTAssertEqual(coldArrival.pending, original)
        app.account.displayNameDraft = "Proof guest"
        await app.account.saveProfile()
        XCTAssertFalse(app.account.needsProfileSetup)
        let confirmation = try XCTUnwrap(coldArrival.confirmation(for: app))
        XCTAssertNil(app.live.pendingIntent, "Auth/profile return never automatically joins")
        XCTAssertTrue(coldArrival.join(confirmation, app: app))
        try await eventually("root original Join first disposition") {
            app.live.serviceNeedsUpdate || (app.live.lastError != nil && !app.live.isCommandInFlight)
        }
        if !app.live.serviceNeedsUpdate {
            let error: String
            switch app.live.lastError {
            case .server(let code): error = code.rawValue
            case .invalidResponse: error = "invalid_response"
            case .unavailable: error = "unavailable"
            case nil: error = "none"
            }
            let diagnostic = try XCTUnwrap(measured)
            let requests = await diagnostic.metrics().requests
            print("ROOT DIAGNOSTIC Join phase \(app.live.phase) error \(error) measuredRequests \(requests) pending \(app.live.pendingIntent != nil)")
            XCTFail("Real root Join did not reach the injected service-update boundary")
            throw IntegrationFailure.timeout
        }
        let pending = try XCTUnwrap(app.live.pendingIntent)
        guard case .join(let originalCommand, _, _, _) = pending else {
            XCTFail("Root Join must persist its complete original command")
            throw IntegrationFailure.timeout
        }
        let recovery = LiveMatchRecoveryStore(rootDirectory: root, userID: admission.receipt.userID)
        XCTAssertEqual(try recovery.load().pendingIntent, pending)
        let service = try XCTUnwrap(measured)
        let requests = await service.metrics().requests
        try await Task.sleep(for: .milliseconds(500))
        let after = await service.metrics().requests
        XCTAssertEqual(after, requests)
        XCTAssertNil(app.live.savedMatchID)
        let replacementCode = code == "ABC234" ? "DEF567" : "ABC234"
        coldArrival.receive(try XCTUnwrap(URL(string: origin + replacementCode)))
        XCTAssertEqual(coldArrival.pending, original, "An arrival needs explicit replacement")
        XCTAssertFalse(coldArrival.join(confirmation, app: app))
        coldArrival.replace()
        let replacement = try XCTUnwrap(coldArrival.pending)
        XCTAssertNotEqual(replacement.replacementGeneration, original.replacementGeneration)
        XCTAssertEqual(app.live.pendingIntent, pending)
        XCTAssertEqual(try recovery.load().pendingIntent, pending)
        XCTAssertNil(app.live.savedMatchID)
        XCTAssertNil(coldArrival.confirmation(for: app), "Replacement cannot bypass an unresolved command")
        app.live.retry()
        try await eventually("root original admission resolves behind newer URL") {
            if app.live.canRetry && app.live.pendingIntent != nil { app.live.retry() }
            return app.live.pendingIntent == nil && app.live.savedMatchID != nil
                && !app.live.isCommandInFlight && !app.live.serviceNeedsUpdate
        }
        if let snapshot = app.live.snapshot {
            XCTAssertEqual(snapshot.match.id, app.live.savedMatchID,
                "Only the explicitly confirmed original admission may resolve")
            XCTAssertEqual(snapshot.match.joinCode, original.code)
        }
        let attemptedJoins = await joinTrace.commands()
        XCTAssertFalse(attemptedJoins.isEmpty)
        XCTAssertTrue(attemptedJoins.allSatisfy { $0 == originalCommand },
            "Every real Join through recovery must retain the original UUID and payload")
        XCTAssertEqual(coldArrival.pending, replacement)
        XCTAssertTrue(coldArrival.isPresented, "Newer invitation remains the presented navigation")
        XCTAssertEqual(app.live.completedInvitationGeneration, original.replacementGeneration)
        XCTAssertEqual(makeInvitations().pending, replacement)
        let restoredRootOwner = makeInvitations()
        restoredRootOwner.bind(app.live, userID: admission.receipt.userID)
        app.invitations = restoredRootOwner
        XCTAssertEqual(restoredRootOwner.pending, replacement, "Old clear preserves newer navigation")
        XCTAssertNil(app.live.completedInvitationGeneration)
        restoredRootOwner.discard() // Explicitly dismiss the newer navigation, not a Join.
        app.live.resumeSavedMatch()
        try await eventually("root confirmed original race reaches play") { app.live.snapshot?.round.state == .playing }
        restoredRootOwner.receive(try XCTUnwrap(URL(string: origin + replacementCode)))
        let nextNavigation = try XCTUnwrap(restoredRootOwner.pending)
        // Retire the real service lifetime and observe its state stream before
        // another identity signs in. Explicit root Sign Out later clears navigation.
        var alternateEnvironment = environment
        alternateEnvironment["GRIDRACE_LIVE_EMAIL"] = try XCTUnwrap(environment["GRIDRACE_ALTERNATE_EMAIL"])
        alternateEnvironment["GRIDRACE_LIVE_PASSWORD"] = try XCTUnwrap(environment["GRIDRACE_ALTERNATE_PASSWORD"])
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let alternate = try LocalIntegrationAdmission.admit(environment: alternateEnvironment, purpose: .live,
            receiptDirectory: support.appending(path: "GridRaceIntegration/Alternate"))
        XCTAssertNotEqual(alternate.receipt.userID, admission.receipt.userID)
        let retirement = await account.signOut()
        XCTAssertNil(retirement.localRecovery)
        XCTAssertFalse(retirement.remoteLogoutFailed)
        try await eventually("root observes actual service retirement") {
            app.account.session == nil && app.live.savedMatchID == nil
        }
        XCTAssertEqual(restoredRootOwner.pending, nextNavigation)
        XCTAssertNil(restoredRootOwner.confirmation(for: app))
        await app.account.signInForLocalTesting(email: alternate.email, password: alternate.password)
        try await eventually("root actual account switch profile") { app.account.profile?.userID == alternate.receipt.userID }
        try alternate.validateIdentity(try XCTUnwrap(app.account.session?.userID))
        XCTAssertNil(app.live.savedMatchID, "Another account cannot adopt prior local recovery")
        XCTAssertNil(app.live.pendingIntent)
        XCTAssertEqual(restoredRootOwner.pending, nextNavigation)
        if app.account.needsProfileSetup {
            app.account.displayNameDraft = "Proof host"
            await app.account.saveProfile()
        }
        XCTAssertFalse(app.account.needsProfileSetup)
        let switchedConfirmation = try XCTUnwrap(restoredRootOwner.confirmation(for: app))
        XCTAssertEqual(switchedConfirmation.userID, alternate.receipt.userID)
        XCTAssertNil(switchedConfirmation.sourceMatchID)
        XCTAssertFalse(restoredRootOwner.join(confirmation, app: app), "Old-account confirmation is obsolete")
        restoredRootOwner.admitted(generation: original.replacementGeneration, userID: admission.receipt.userID)
        XCTAssertEqual(restoredRootOwner.pending, nextNavigation)
        XCTAssertFalse(restoredRootOwner.storageFailed)
        await app.account.signOut()
        XCTAssertNil(restoredRootOwner.pending)
        XCTAssertTrue(app.isDailyPlayable)
        print("PASS live client actual root signedout profile confirmed Join replacement owner reload clear account transition fences")
    }

    private func runRematchSignalRole(
        _ role: String, service: MeasuredLiveMatchService,
        realtime: any LiveMatchRealtimeServicing, predecessor: UUID
    ) async throws {
        if role == "friends-signal-guest" {
            for action in [LiveRematchAction.offer, .cancel, .offer, .cancel] {
                let snapshot = try await service.snapshot(matchID: predecessor)
                let rematch = try XCTUnwrap(snapshot.rematch)
                let command = LiveRematchCommand(requestID: UUID(), predecessorMatchID: predecessor,
                    generation: action == .offer ? (rematch.nextGeneration ?? rematch.generation) : rematch.generation,
                    action: action, expectedParticipationEpoch: snapshot.selection.epoch, clientBuild: 3)
                do { _ = try await service.rematch(command) }
                catch LiveMatchServiceError.unavailable { _ = try await service.rematch(command) }
                // Keep these real revisions distinct; no gameplay command occurs.
                try await Task.sleep(for: .milliseconds(250))
            }
            print("PASS live client real rematch-only offer cancel fresh offer cancel")
            return
        }
        let initial = try await service.snapshot(matchID: predecessor)
        let observation = RematchRealtimeObservation()
        let faulted = FaultedRealtimeService(base: realtime, observation: observation)
        let consumer = Task {
            for try await event in faulted.events(matchID: predecessor) {
                if event == .signal { await observation.delivered() }
            }
        }
        defer { consumer.cancel() }
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !(await observation.state().ready) {
            guard ContinuousClock.now < readyDeadline else { throw IntegrationFailure.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GridRaceIntegration")
        try Data("ready".utf8).write(to: root.appending(path: "rematch-signal-listening"), options: .atomic)
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        var state = await observation.state()
        while state.raw < 4 || state.dropped < 1 || state.reordered < 1 || state.delivered < 1 {
            guard ContinuousClock.now < deadline else { throw IntegrationFailure.timeout }
            try await Task.sleep(for: .milliseconds(100))
            state = await observation.state()
        }
        // No session or polling timer has been opened. Removing the production
        // rematch subscriptions makes the signal assertion time out before this read.
        print("PASS live client real native rematch-only Realtime delivery before canonical polling")
        let canonical = try await service.snapshot(matchID: predecessor)
        XCTAssertEqual(canonical.revision, initial.revision, "Gameplay stream cannot supply these signals")
        XCTAssertEqual(canonical.revealedRounds, initial.revealedRounds)
        XCTAssertEqual(canonical.rematch?.state, .closed)
        XCTAssertEqual(canonical.rematch?.generation, 2)
        print("PASS live client dropped reordered real rematch signals canonical closure recovery")
    }

    private func runFriendsRole(
        _ role: String, session: LiveMatchSession, service: MeasuredLiveMatchService,
        store: LiveMatchRecoveryStore, predecessor: UUID, count: Int
    ) async throws {
        // Account binding already restores and starts recovery. Restarting it here
        // would cancel the controlled predecessor read before the third client acts.
        if role != "friends-race" { session.resumeSavedMatch() }
        try await eventually("friends canonical recovery", timeout: role == "friends-race" ? 130 : 60) {
            if session.canRetry && session.pendingIntent != nil { session.retry() }
            return session.snapshot != nil && session.pendingIntent == nil
        }
        if ["friends-offer", "friends-cancel", "friends-decline", "friends-close-disabled"].contains(role) {
            let action: LiveRematchAction = role == "friends-offer" ? .offer : (role == "friends-cancel" ? .cancel : .decline)
            try await eventually("explicit consent lifecycle action") { session.availableRematchActions.contains(action) }
            session.performRematch(action)
            let expected: LiveRematchState = role == "friends-offer" ? .offered : (role == "friends-close-disabled" ? .unavailable : .closed)
            try await eventually("definitive lifecycle receipt") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.pendingIntent == nil && session.snapshot?.rematch?.state == expected
            }
            XCTAssertEqual(session.savedMatchID, predecessor)
            print("PASS live client explicit \(action.rawValue) definitive \(expected.rawValue) generation \(session.snapshot?.rematch?.generation ?? 0)")
        } else if role == "friends-both" {
            XCTAssertEqual(session.snapshot?.match.id, predecessor)
            XCTAssertEqual(session.snapshot?.match.status, .completed)
            try await eventually("rematch consent entry") {
                session.availableRematchActions.contains(.offer) || session.availableRematchActions.contains(.accept)
            }
            session.performRematch(session.availableRematchActions.contains(.offer) ? .offer : .accept)
            try await eventually("same pair successor", timeout: 90) {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.savedMatchID != predecessor && session.pendingIntent == nil && session.snapshot?.match.status == .lobby
            }
            let successor = try XCTUnwrap(session.savedMatchID)
            XCTAssertEqual(session.snapshot?.match.admission, .rematch)
            XCTAssertEqual(session.snapshot?.match.roundCount, count)
            XCTAssertEqual(session.snapshot?.members.count, 2)
            XCTAssertEqual(session.snapshot?.round.state, .pending)
            let command = try await service.originalRematchCommand()
            // The reply was accepted by real Edge/DB. Recreate death before saving
            // admission, then the next independent process replays the exact command.
            try store.save(LiveRecoveryState(matchID: predecessor,
                pendingIntent: .rematch(command: command, sourceMatchID: predecessor, navigationGeneration: UUID())))
            session.leaveToHome()
            print("PASS live client simultaneous consent private successor no resharing count \(count)")
            print("INJECTION persisted accepted original rematch for separate-process relaunch")
            XCTAssertNotEqual(successor, predecessor)
        } else if role == "friends-recover" {
            XCTAssertNotEqual(session.savedMatchID, predecessor)
            XCTAssertEqual(session.snapshot?.match.status, .lobby)
            XCTAssertEqual(session.snapshot?.match.roundCount, count)
            XCTAssertEqual(session.snapshot?.round.state, .pending)
            let old = try await service.snapshot(matchID: predecessor)
            XCTAssertEqual(old.match.status, .completed)
            XCTAssertEqual(old.revealedRounds.count, count)
            print("PASS live client receipt-first process relaunch and accepted rollback recovery count \(count)")
        } else if role == "friends-select" {
            session.leaveToHome()
            session.createMatch(roundCount: 1)
            try await eventually("third process selects other race") {
                session.pendingIntent == nil && session.snapshot?.match.status == .lobby
                    && session.snapshot?.match.admission == .code
            }
            print("PASS live client third same-account process selected another race epoch \(session.snapshot?.selection.epoch ?? -1)")
        } else if role == "friends-stale" || role == "friends-race" {
            if role == "friends-race" {
                let deadline = ContinuousClock.now.advanced(by: .seconds(20))
                while !(await service.selectionRaceReadObserved()) {
                    guard ContinuousClock.now < deadline else { throw IntegrationFailure.timeout }
                    try await Task.sleep(for: .milliseconds(50))
                }
                let expectedTarget = try await service.selectionRaceTarget()
                // The predecessor is published before the awaited successor read.
                // Wait for its consumption; a removed guard takes the wrong-pointer
                // branch and must fail the assertion below, never this wait.
                try await eventually("second canonical read consumed", timeout: 20) {
                    (session.resumeConfirmationTarget?.match.id == expectedTarget.id
                        && session.resumeConfirmationTarget?.selection.epoch == expectedTarget.epoch)
                        || session.savedMatchID != predecessor
                }
                try await service.assertSelectionRaceRead()
            }
            XCTAssertEqual(session.savedMatchID, predecessor)
            XCTAssertTrue(session.requiresResumeConfirmation)
            let beforePassive = try await service.snapshot(matchID: predecessor)
            let epoch = beforePassive.selection.epoch
            XCTAssertFalse(beforePassive.selection.isSelected)
            session.backgrounded(); session.foregrounded()
            try await eventually("passive current epoch convergence") { session.snapshot?.selection.epoch == epoch }
            XCTAssertEqual(session.savedMatchID, predecessor)
            let passive = try await service.snapshot(matchID: predecessor)
            XCTAssertEqual(passive.selection.epoch, epoch)
            XCTAssertFalse(passive.selection.isSelected)
            XCTAssertTrue(session.availableRematchActions.isEmpty)
            session.confirmResumeSavedMatch()
            try await eventually("explicit pinned successor Resume") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.savedMatchID != predecessor && session.snapshot?.selection.isSelected == true
            }
            let joined = try await service.originalJoinCommand()
            XCTAssertEqual(joined.expectedMatchID, session.savedMatchID)
            XCTAssertEqual(joined.clientBuild, 3)
            print("PASS live client stale pointer passive epoch unchanged then explicit pinned Resume")
        } else if role == "friends-resume" {
            XCTAssertEqual(session.snapshot?.match.id, predecessor)
            try await assertReveal(session, count: count, target: count)
            print("PASS live client friends completed current successor process relaunch")
        } else { XCTFail("Unknown friends role") }
        session.leaveToHome()
    }

    private func finishRound(_ session: LiveMatchSession, guess: String, solved: Bool = false) async throws {
        for _ in 0..<6 {
            guard selfPlayer(in: session.snapshot)?.state == .playing else { break }
            try await eventually("input ready") {
                !session.isInputLocked && !session.isCommandInFlight
            }
            let prior = selfPlayer(in: session.snapshot)?.acceptedGuessCount ?? 0
            session.submitGuess(guess)
            try await eventually("accepted guess") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                guard !session.isCommandInFlight,
                      let player = self.selfPlayer(in: session.snapshot)
                else {
                    return false
                }
                return player.acceptedGuessCount > prior || player.state.isTerminal
            }
        }
        try await eventually("terminal player") {
            session.pendingIntent == nil && !session.isCommandInFlight
                && self.selfPlayer(in: session.snapshot)?.state.isTerminal == true
        }
        let player = try XCTUnwrap(selfPlayer(in: session.snapshot))
        XCTAssertEqual(player.state, solved ? .solved : .failed)
        XCTAssertEqual(player.acceptedGuessCount, solved ? 1 : 6)
        XCTAssertEqual(player.efficiencyPoints, solved ? 6 : 0)
        XCTAssertTrue(session.pendingIntent == nil)
        XCTAssertTrue(session.guessDraft.isEmpty)
        print("PASS live client terminal path: accepted count/efficiency/intent verified")
    }

    private func assertReveal(
        _ session: LiveMatchSession, count: Int, target: Int, incomplete: Bool = false
    ) async throws {
        try await eventually("canonical reveal", timeout: 90) {
            session.snapshot?.round.state == .revealed
        }
        let snapshot = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(snapshot.match.status, incomplete ? .incomplete : (target == count ? .completed : .inProgress))
        XCTAssertEqual(snapshot.match.roundCount, count)
        XCTAssertEqual(snapshot.match.currentRound, target)
        XCTAssertEqual(snapshot.round.number, target)
        XCTAssertEqual(snapshot.revealedRounds.map(\.number), Array(1...target))
        XCTAssertTrue(snapshot.revealedRounds.last == snapshot.round)
        XCTAssertEqual(Set(snapshot.revealedRounds.compactMap(\.answer)).count, target)
        let standings = try XCTUnwrap(snapshot.standings)
        XCTAssertEqual(standings.throughRound, target)
        XCTAssertEqual(standings.isFinal, target == count)
        XCTAssertEqual(standings.players.count, 2)
        if incomplete { XCTAssertEqual(snapshot.match.terminalReason, .accountDeleted) }
        if snapshot.match.terminalReason == .accountDeleted {
            XCTAssertEqual(snapshot.members.filter(\.isSelf).count, 1)
            XCTAssertEqual(snapshot.members.filter(\.isDeleted).count, 1)
            XCTAssertFalse(snapshot.members.first(where: \.isDeleted)?.isSelf ?? true)
        }
        if snapshot.round.players.allSatisfy({ $0.state == .failed || $0.state == .timedOut }) {
            XCTAssertTrue(standings.players.allSatisfy {
                $0.roundsSolved == 0 && $0.efficiencyPoints == 0 && $0.placement == 1
            })
        }
        XCTAssertEqual(snapshot.members.count, 2)
        XCTAssertEqual(snapshot.round.players.count, 2)
        XCTAssertEqual(snapshot.round.answer?.count, 5)
        XCTAssertTrue(snapshot.round.players.allSatisfy { $0.state.isTerminal })
        XCTAssertTrue(snapshot.round.players.allSatisfy { $0.board != nil && $0.placement != nil })
    }

    private func selfPlayer(in snapshot: LiveMatchSnapshot?) -> LiveRoundPlayer? {
        guard let snapshot,
              let memberID = snapshot.members.first(where: \.isSelf)?.id
        else { return nil }
        return snapshot.round.players.first { $0.memberID == memberID }
    }

    private func eventually(
        _ name: String,
        timeout: TimeInterval = 60,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for \(name)")
        throw IntegrationFailure.timeout
    }
}

/// The root may construct several account-bound transports. Record actual Join
/// attempts across their wrappers without changing any production transport.
private actor IntegrationJoinTrace {
    private var attempts: [LiveJoinCommand] = []
    func record(_ command: LiveJoinCommand) { attempts.append(command) }
    func commands() -> [LiveJoinCommand] { attempts }
}

private actor MeasuredLiveMatchService: LiveMatchServicing {
    private let base: any LiveMatchServicing
    private var requestCount = 0
    private var maximumLatencyMilliseconds = 0

    private var loseCreate: Bool
    private var loseStart: Bool
    private var loseGuess: Bool
    private var updateJoin: Bool
    private var loseJoin: Bool
    private var loseRematch: Bool
    private var joins: [UUID: LiveJoinCommand] = [:]
    private let joinTrace: IntegrationJoinTrace?
    private var rematches: [UUID: LiveRematchCommand] = [:]
    private var lastJoin: LiveJoinCommand?
    private var lastRematch: LiveRematchCommand?
    private var selectionBarrier: Bool
    private var raceSuccessor: UUID?
    private var racePredecessorEpoch: Int64?
    private var raceSuccessorEpoch: Int64?
    private var observedNewerUnselectedSuccessor = false
    private var closureBarrier: Bool
    private var originalGuess: (round: Int, id: UUID, word: String, build: Int, receipt: LiveGuessReceipt)?

    private let target: Int
    private let waitForAdvance: Bool
    private var delayedOldReceipt = false

    init(_ base: any LiveMatchServicing, injectLoss: Bool, target: Int, waitForAdvance: Bool, friends: Bool = false, selectionBarrier: Bool = false, closureBarrier: Bool = false, joinTrace: IntegrationJoinTrace? = nil) {
        self.base = base
        self.joinTrace = joinTrace
        self.target = target
        self.waitForAdvance = waitForAdvance
        loseCreate = injectLoss
        loseStart = injectLoss
        loseGuess = injectLoss
        self.selectionBarrier = selectionBarrier
        self.closureBarrier = closureBarrier
        updateJoin = friends; loseJoin = friends; loseRematch = friends
    }

    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID {
        let result = try await measure {
            try await base.createMatch(requestID: requestID, roundCount: roundCount, clientBuild: clientBuild)
        }
        if loseCreate {
            loseCreate = false
            print("INJECTION dropped real Create response")
            throw LiveMatchServiceError.unavailable
        }
        return result
    }

    func joinMatch(_ command: LiveJoinCommand) async throws -> UUID {
        if let prior = joins[command.requestID] { XCTAssertEqual(prior, command, "Retry retains exact Join payload") }
        joins[command.requestID] = command; lastJoin = command
        await joinTrace?.record(command)
        let result = try await measure { try await base.joinMatch(command) }
        if updateJoin {
            updateJoin = false
            print("INJECTION current service update response after real Join acceptance")
            throw LiveMatchServiceError.server(.clientUpdateRequired)
        }
        if loseJoin { loseJoin = false; print("INJECTION dropped real Join response"); throw LiveMatchServiceError.unavailable }
        return result
    }

    func rematch(_ command: LiveRematchCommand) async throws -> LiveRematchReceipt {
        if let prior = rematches[command.requestID] { XCTAssertEqual(prior, command, "Retry retains exact rematch payload") }
        rematches[command.requestID] = command; lastRematch = command
        if closureBarrier {
            closureBarrier = false
            try await waitForControllerBarrier("closure")
        }
        let result = try await measure { try await base.rematch(command) }
        if loseRematch { loseRematch = false; print("INJECTION dropped real rematch consent response"); throw LiveMatchServiceError.unavailable }
        return result
    }

    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID {
        let result = try await measure { try await base.startMatch(id: id, roundNumber: roundNumber) }
        if loseStart {
            loseStart = false
            print("INJECTION dropped real Start response")
            throw LiveMatchServiceError.unavailable
        }
        return result
    }

    func submitGuess(
        matchID: UUID,
        roundNumber: Int,
        requestID: UUID,
        guess: String,
        clientBuild: Int
    ) async throws -> LiveGuessReceipt {
        let result = try await measure {
            try await base.submitGuess(matchID: matchID, roundNumber: roundNumber, requestID: requestID,
                                       guess: guess, clientBuild: clientBuild)
        }
        if originalGuess == nil && roundNumber == target { originalGuess = (roundNumber, requestID, guess, clientBuild, result) }
        if roundNumber < target && !delayedOldReceipt {
            delayedOldReceipt = true
            print("INJECTION delayed real old-round receipt")
            if waitForAdvance {
                let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                var advanced = false
                while ContinuousClock.now < deadline {
                    let canonical = try await base.snapshot(matchID: matchID)
                    if canonical.match.currentRound == target { advanced = true; break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                XCTAssertTrue(advanced, "old receipt must arrive after creator advanced")
                print("PASS real old-round receipt released after later-round Start")
            } else {
                try await Task.sleep(for: .seconds(1))
            }
        }
        if loseGuess && roundNumber == target {
            loseGuess = false
            print("INJECTION dropped real accepted Guess response")
            throw LiveMatchServiceError.unavailable
        }
        return result
    }

    private func waitForControllerBarrier(_ name: String) async throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GridRaceIntegration")
        try Data("waiting".utf8).write(to: root.appending(path: "\(name)-read-barrier"), options: .atomic)
        print("BARRIER \(name) actual read waiting for controller")
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        while !FileManager.default.fileExists(atPath: root.appending(path: "\(name)-read-release").path) {
            guard ContinuousClock.now < deadline else { throw IntegrationFailure.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func originalRematchCommand() throws -> LiveRematchCommand {
        guard let lastRematch else { throw IntegrationFailure.timeout }; return lastRematch
    }
    func originalJoinCommand() throws -> LiveJoinCommand {
        guard let lastJoin else { throw IntegrationFailure.timeout }; return lastJoin
    }

    func acceptedIntent(matchID: UUID) throws -> LivePendingIntent {
        guard let originalGuess else { throw IntegrationFailure.timeout }
        return .guess(matchID: matchID, requestID: originalGuess.id, word: originalGuess.word,
                      roundNumber: originalGuess.round, clientBuild: originalGuess.build)
    }

    func assertReceiptReplay(matchID: UUID) async throws {
        guard let originalGuess else { throw IntegrationFailure.timeout }
        let replay = try await base.submitGuess(
            matchID: matchID, roundNumber: originalGuess.round, requestID: originalGuess.id,
            guess: originalGuess.word, clientBuild: originalGuess.build
        )
        XCTAssertTrue(replay == originalGuess.receipt)
        do {
            _ = try await base.submitGuess(
                matchID: matchID, roundNumber: originalGuess.round, requestID: originalGuess.id,
                guess: "aaaaa", clientBuild: originalGuess.build
            )
            XCTFail("changed accepted payload must conflict")
        } catch LiveMatchServiceError.server(.requestConflict) {}
        print("PASS real accepted receipt replay/conflict")
    }

    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot {
        let snapshot = try await measure { try await base.snapshot(matchID: matchID) }
        if selectionBarrier && snapshot.rematch?.state == .accepted && snapshot.rematch?.selectedElsewhere == false {
            print("BARRIER selection canonical predecessor epoch \(snapshot.selection.epoch) selected \(snapshot.selection.isSelected) elsewhere \(snapshot.rematch?.selectedElsewhere ?? true)")
            try await waitForControllerBarrier("selection")
            selectionBarrier = false
            raceSuccessor = snapshot.rematch?.successorMatchID
            racePredecessorEpoch = snapshot.selection.epoch
            print("INJECTION third-account selection between real predecessor and successor reads")
        }
        if matchID == raceSuccessor, let oldEpoch = racePredecessorEpoch,
           snapshot.selection.epoch > oldEpoch, !snapshot.selection.isSelected {
            raceSuccessorEpoch = snapshot.selection.epoch
            observedNewerUnselectedSuccessor = true
            print("PASS real successor read observes newer unselected epoch \(snapshot.selection.epoch) after predecessor \(oldEpoch)")
        }
        return snapshot
    }

    func selectionRaceTarget() throws -> (id: UUID, epoch: Int64) {
        guard let raceSuccessor, let raceSuccessorEpoch else { throw IntegrationFailure.timeout }
        return (raceSuccessor, raceSuccessorEpoch)
    }

    func selectionRaceReadObserved() -> Bool { observedNewerUnselectedSuccessor }

    func assertSelectionRaceRead() throws {
        XCTAssertTrue(observedNewerUnselectedSuccessor, "The third process must move selection between actual predecessor/successor reads")
        guard observedNewerUnselectedSuccessor else { throw IntegrationFailure.timeout }
    }

    func metrics() -> (requests: Int, maximumLatencyMilliseconds: Int) {
        (requestCount, maximumLatencyMilliseconds)
    }

    private func measure<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let clock = ContinuousClock()
        let started = clock.now
        defer {
            requestCount += 1
            let elapsed = started.duration(to: clock.now).components
            maximumLatencyMilliseconds = max(
                maximumLatencyMilliseconds,
                Int(elapsed.seconds) * 1_000
                    + Int(elapsed.attoseconds / 1_000_000_000_000_000)
            )
        }
        return try await operation()
    }
}

// Faults apply to real Realtime signals; authoritative snapshots are untouched.
private actor RematchRealtimeObservation {
    private var isReady = false
    private var raw = 0, dropped = 0, reordered = 0, deliveredCount = 0
    func ready() { isReady = true }
    func received() { raw += 1 }
    func drop() { dropped += 1 }
    func reorder() { reordered += 1 }
    func delivered() { deliveredCount += 1 }
    func state() -> (ready: Bool, raw: Int, dropped: Int, reordered: Int, delivered: Int) {
        (isReady, raw, dropped, reordered, deliveredCount)
    }
}

private struct FaultedRealtimeService: LiveMatchRealtimeServicing {
    let base: any LiveMatchRealtimeServicing
    var observation: RematchRealtimeObservation? = nil

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffered: LiveMatchRealtimeEvent?
                var count = 0
                do {
                    for try await event in base.events(matchID: matchID) {
                        try Task.checkCancellation()
                        if event == .ready { await observation?.ready() }
                        guard event == .signal else { continuation.yield(event); continue }
                        await observation?.received()
                        count += 1
                        if count % 3 == 0 {
                            await observation?.drop()
                            print("INJECTION dropped real Realtime signal")
                            continue
                        }
                        if count % 3 == 1 { buffered = event; continue }
                        continuation.yield(event)
                        continuation.yield(event)
                        if let delayed = buffered {
                            continuation.yield(delayed)
                            buffered = nil
                            await observation?.reorder()
                            print("INJECTION duplicated and reordered real Realtime signals")
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct PublicFixtureCode: Decodable { let code: String }
private enum IntegrationFailure: Error { case timeout }
