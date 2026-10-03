import Foundation
import XCTest
@testable import GridRace

@MainActor
final class LiveMatchIntegrationTests: XCTestCase {
    func testTwoClientProcess() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GRIDRACE_LOCAL_INTEGRATION"] == "1",
              let role = environment["GRIDRACE_LIVE_ROLE"],
              let scenario = environment["GRIDRACE_LIVE_SCENARIO"],
              let email = environment["GRIDRACE_LIVE_EMAIL"],
              let password = environment["GRIDRACE_LIVE_PASSWORD"],
              let failedGuess = environment["GRIDRACE_LIVE_FAILED_GUESS"],
              let url = environment["GRIDRACE_LOCAL_SUPABASE_URL"],
              let key = environment["GRIDRACE_LOCAL_SUPABASE_KEY"]
        else {
            throw XCTSkip(
                "P4-V requires GRIDRACE_LOCAL_INTEGRATION=1 and the host orchestration environment"
            )
        }
        XCTAssertTrue(environment["SERVICE_ROLE_KEY"] == nil)
        XCTAssertTrue(environment["SUPABASE_SERVICE_ROLE_KEY"] == nil)
        XCTAssertTrue(environment["SUPABASE_SECRET_KEY"] == nil)
        XCTAssertTrue(environment["DB_URL"] == nil)
        XCTAssertTrue(environment["JWT_SECRET"] == nil)

        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: url,
            publishableKey: key
        ))
        XCTAssertTrue(["127.0.0.1", "localhost"].contains(configuration.projectURL.host()))
        let account = SupabaseAccountService(configuration: configuration)
        let signedIn = try await account.signInForLocalTesting(email: email, password: password)
        let count = Int(environment["GRIDRACE_LIVE_ROUND_COUNT"] ?? "1") ?? 0
        let target = Int(environment["GRIDRACE_LIVE_ROUND_NUMBER"] ?? "1") ?? 0
        XCTAssertTrue([1, 3, 5].contains(count))
        XCTAssertTrue((1...count).contains(target))
        let service = MeasuredLiveMatchService(
            account.makeLiveMatchService(), injectLoss: scenario == "product" && role != "resume",
            target: target, waitForAdvance: role == "advance-guest"
        )
        let realtime: (any LiveMatchRealtimeServicing)? =
            environment["GRIDRACE_LIVE_DISABLE_REALTIME"] == "1"
            ? nil
            : FaultedRealtimeService(base: account.makeLiveRealtimeService())
        let session = LiveMatchSession(service: service, realtime: realtime)
        session.changeAccount(to: signedIn.userID)
        if session.pendingIntent != nil { XCTAssertTrue(session.isInputLocked) }

        if role == "host" {
            session.createMatch(roundCount: count)
            try await eventually("host create") {
                if session.canRetry && session.pendingIntent != nil { session.retry() }
                return session.phase == .ready && session.snapshot?.members.isEmpty == false
            }
            XCTAssertEqual(session.snapshot?.match.roundCount, count)
            try await eventually("guest roster") { session.snapshot?.members.count == 2 }
        } else if role == "guest" {
            session.joinMatch(code: try XCTUnwrap(environment["GRIDRACE_LIVE_JOIN_CODE"]))
            try await eventually("guest roster") {
                session.phase == .ready && session.snapshot?.members.count == 2
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
        if scenario == "product" || role.hasPrefix("solve-") {
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

        let metrics = await service.metrics()
        XCTAssertGreaterThan(metrics.requests, 0)
        XCTAssertLessThan(metrics.maximumLatencyMilliseconds, 10_000)
        print(
            "PASS live client \(role) \(scenario) \(metrics.requests) requests "
                + "\(metrics.maximumLatencyMilliseconds)ms max"
        )
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

private actor MeasuredLiveMatchService: LiveMatchServicing {
    private let base: any LiveMatchServicing
    private var requestCount = 0
    private var maximumLatencyMilliseconds = 0

    private var loseCreate: Bool
    private var loseStart: Bool
    private var loseGuess: Bool
    private var originalGuess: (round: Int, id: UUID, word: String, build: Int, receipt: LiveGuessReceipt)?

    private let target: Int
    private let waitForAdvance: Bool
    private var delayedOldReceipt = false

    init(_ base: any LiveMatchServicing, injectLoss: Bool, target: Int, waitForAdvance: Bool) {
        self.base = base
        self.target = target
        self.waitForAdvance = waitForAdvance
        loseCreate = injectLoss
        loseStart = injectLoss
        loseGuess = injectLoss
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

    func joinMatch(code: String) async throws -> UUID {
        try await measure { try await base.joinMatch(code: code) }
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
        try await measure { try await base.snapshot(matchID: matchID) }
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
private struct FaultedRealtimeService: LiveMatchRealtimeServicing {
    let base: any LiveMatchRealtimeServicing

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffered: LiveMatchRealtimeEvent?
                var count = 0
                do {
                    for try await event in base.events(matchID: matchID) {
                        try Task.checkCancellation()
                        guard event == .signal else { continuation.yield(event); continue }
                        count += 1
                        if count % 3 == 0 {
                            print("INJECTION dropped real Realtime signal")
                            continue
                        }
                        if count % 3 == 1 { buffered = event; continue }
                        continuation.yield(event)
                        continuation.yield(event)
                        if let delayed = buffered {
                            continuation.yield(delayed)
                            buffered = nil
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

private enum IntegrationFailure: Error { case timeout }
