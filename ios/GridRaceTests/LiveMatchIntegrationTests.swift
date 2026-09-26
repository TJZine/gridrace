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
                "P3-04 requires GRIDRACE_LOCAL_INTEGRATION=1 and the host orchestration environment"
            )
        }
        XCTAssertNil(environment["SERVICE_ROLE_KEY"])
        XCTAssertNil(environment["SUPABASE_SERVICE_ROLE_KEY"])
        XCTAssertNil(environment["SUPABASE_SECRET_KEY"])
        XCTAssertNil(environment["DB_URL"])
        XCTAssertNil(environment["JWT_SECRET"])

        let configuration = try XCTUnwrap(SupabaseAccountService.Configuration(
            urlString: url,
            publishableKey: key
        ))
        XCTAssertTrue(["127.0.0.1", "localhost"].contains(configuration.projectURL.host()))
        let account = SupabaseAccountService(configuration: configuration)
        let signedIn = try await account.signInForLocalTesting(email: email, password: password)
        let service = MeasuredLiveMatchService(account.makeLiveMatchService())
        let realtime: (any LiveMatchRealtimeServicing)? =
            environment["GRIDRACE_LIVE_DISABLE_REALTIME"] == "1"
            ? nil
            : account.makeLiveRealtimeService()
        let session = LiveMatchSession(service: service, realtime: realtime)
        session.changeAccount(to: signedIn.userID)

        switch role {
        case "host":
            session.createMatch()
            try await eventually("host create") {
                session.phase == .ready && session.snapshot?.members.count == 1
            }
            try await eventually("guest roster") { session.snapshot?.members.count == 2 }
            session.startMatch()
            try await eventually("host playing") { session.snapshot?.round.state == .playing }
            if scenario == "product" {
                try await finishRound(session, guess: failedGuess)
                try await assertReveal(session)
            }
        case "guest":
            let code = try XCTUnwrap(environment["GRIDRACE_LIVE_JOIN_CODE"])
            session.joinMatch(code: code)
            try await eventually("guest roster") {
                session.phase == .ready && session.snapshot?.members.count == 2
            }
            try await eventually("guest playing") { session.snapshot?.round.state == .playing }
            if scenario == "product" {
                try await finishRound(session, guess: failedGuess)
                try await assertReveal(session)
            }
        case "resume":
            let expected = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(
                environment["GRIDRACE_LIVE_MATCH_ID"]
            )))
            XCTAssertEqual(session.savedMatchID, expected, "relaunch must restore its own container")
            try await assertReveal(session)
        default:
            XCTFail("Unknown host-controlled integration role")
        }

        let metrics = await service.metrics()
        XCTAssertGreaterThan(metrics.requests, 0)
        XCTAssertLessThan(metrics.maximumLatencyMilliseconds, 10_000)
        print(
            "PASS live client \(role) \(scenario) \(metrics.requests) requests "
                + "\(metrics.maximumLatencyMilliseconds)ms max"
        )
    }

    private func finishRound(_ session: LiveMatchSession, guess: String) async throws {
        for _ in 0..<6 {
            guard selfPlayer(in: session.snapshot)?.state == .playing else { break }
            let prior = selfPlayer(in: session.snapshot)?.acceptedGuessCount ?? 0
            session.submitGuess(guess)
            try await eventually("accepted guess") {
                guard !session.isCommandInFlight,
                      let player = self.selfPlayer(in: session.snapshot)
                else {
                    return false
                }
                return player.acceptedGuessCount > prior || player.state.isTerminal
            }
        }
        try await eventually("terminal player") {
            self.selfPlayer(in: session.snapshot)?.state.isTerminal == true
        }
        let player = try XCTUnwrap(selfPlayer(in: session.snapshot))
        XCTAssertEqual(player.state, .failed)
        XCTAssertEqual(player.acceptedGuessCount, 6)
        XCTAssertEqual(player.efficiencyPoints, 0)
        XCTAssertNil(session.pendingIntent)
        XCTAssertEqual(session.guessDraft, "")
        print("PASS live client failed path: six guesses, failed, zero efficiency, intent cleared")
    }

    private func assertReveal(_ session: LiveMatchSession) async throws {
        try await eventually("canonical reveal", timeout: 90) {
            session.snapshot?.round.state == .revealed
        }
        let snapshot = try XCTUnwrap(session.snapshot)
        XCTAssertEqual(snapshot.match.status, .completed)
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

    init(_ base: any LiveMatchServicing) { self.base = base }

    func createMatch(requestID: UUID) async throws -> UUID {
        try await measure { try await base.createMatch(requestID: requestID) }
    }

    func joinMatch(code: String) async throws -> UUID {
        try await measure { try await base.joinMatch(code: code) }
    }

    func startMatch(id: UUID) async throws -> UUID {
        try await measure { try await base.startMatch(id: id) }
    }

    func submitGuess(
        matchID: UUID,
        requestID: UUID,
        guess: String
    ) async throws -> LiveGuessReceipt {
        try await measure {
            try await base.submitGuess(matchID: matchID, requestID: requestID, guess: guess)
        }
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

private enum IntegrationFailure: Error { case timeout }
