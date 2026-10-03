import Foundation
import XCTest
import SwiftUI
import UIKit
@testable import GridRace

final class LiveMatchViewTests: XCTestCase {
    func testJoinCodeNormalizationIsPresentationOnly() {
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("abC234"), "ABC234")
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("abc234extra"), "ABC234")
        XCTAssertEqual(LiveMatchPresentation.normalizedJoinCode("a-b"), "A-B")
    }

    func testCountdownUsesCanonicalDisplayedServerTime() {
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-5)), 3)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-2.01)), 3)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start.addingTimeInterval(-1)), 1)
        XCTAssertEqual(LiveMatchPresentation.countdownSeconds(startsAt: start, displayedServerTime: start), 0)
    }

    func testStartRequiresCreatorFullCanonicalLobbyBeforeExpiryAndNoCommand() {
        let snapshot = Self.snapshot(status: .lobby, roundState: .pending, selfSeat: 1)
        let now = snapshot.serverTime

        XCTAssertTrue(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: now,
            isCommandInFlight: false
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: now,
            isCommandInFlight: true
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: Self.snapshot(status: .lobby, roundState: .pending, selfSeat: 2),
            displayedServerTime: now,
            isCommandInFlight: false
        ))
        XCTAssertFalse(LiveMatchPresentation.canStart(
            snapshot: snapshot,
            displayedServerTime: snapshot.match.expiresAt,
            isCommandInFlight: false
        ))
    }

    func testCountdownAccessibilityIncludesRoundAndDeletionBoundary() throws {
        let countdown = try Phase4LiveFixtures.snapshot("3-round-2-countdown")
        XCTAssertEqual(LiveMatchPresentation.countdownLabel(countdown, seconds: 2), "Round 2 of 3, Live race starts in 2")
        let deleted = try Phase4LiveFixtures.snapshot("deletion-active")
        XCTAssertTrue(LiveMatchPresentation.countdownLabel(deleted, seconds: 0).contains("remaining rounds cannot start"))
    }

    func testOpponentAccessibilityLabelContainsOnlyCoarseProgress() {
        let member = Self.member(seat: 2, isSelf: false)
        let player = LiveRoundPlayer(
            memberID: member.id,
            state: .playing,
            acceptedGuessCount: 3,
            solveDurationMilliseconds: nil,
            efficiencyPoints: nil,
            placement: nil,
            board: nil
        )

        let label = LiveMatchPresentation.opponentAccessibilityLabel(member: member, player: player)

        XCTAssertEqual(label, "Opponent Player 2, 3 guesses submitted, still playing.")
        XCTAssertFalse(label.contains(member.id.uuidString))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("feedback"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("time"))
    }

    func testRevealOrdersSelfFirstThenSeatAndPreservesRows() {
        let snapshot = Self.snapshot(status: .completed, roundState: .revealed, selfSeat: 2)

        let boards = LiveMatchPresentation.revealBoards(snapshot: snapshot)

        XCTAssertEqual(boards.map(\.member.seat), [2, 1])
        XCTAssertEqual(boards[0].rows.map(\.sequence), [1, 2])
        XCTAssertEqual(boards[0].rows.map(\.word), ["adore", "vivid"])
        XCTAssertEqual(boards[1].rows.map(\.sequence), [1])
    }

    func testEveryErrorHasConciseSafePresentation() {
        for error in LiveMatchServerError.allCases {
            let message = LiveMatchPresentation.errorMessage(.server(error))
            XCTAssertNotNil(message)
            XCTAssertLessThan(message?.count ?? .max, 100)
            XCTAssertFalse(message?.contains("ABC234") == true)
            XCTAssertFalse(message?.contains("00000000-") == true)
        }
        XCTAssertNotNil(LiveMatchPresentation.errorMessage(.invalidResponse))
        XCTAssertNotNil(LiveMatchPresentation.errorMessage(.unavailable))
    }

    @MainActor
    func testCreateControlsDefaultAndSelectionsReachDurableOriginalIntent() async throws {
        for selected in [1, 3, 5] {
            let snapshot = try Phase4LiveFixtures.snapshot("3-lobby")
            let store = PresentationRecoveryStore(LiveRecoveryState())
            let session = LiveMatchSession(service: PresentationService(snapshot), realtime: nil,
                                           storeFactory: { _ in store })
            session.changeAccount(to: UUID())
            var routes: [AppRoute] = []
            let controls = LiveCreateControls(live: session, isSignedIn: true,
                                              openRoute: { routes.append($0) }, roundCount: selected)
            try await captureCreate(controls, name: "native-create-\(selected)")
            controls.create()
            guard case .create(_, let count, let build) = try store.load().pendingIntent else {
                return XCTFail("Create must persist its selected configuration before dispatch")
            }
            XCTAssertEqual(count, selected)
            XCTAssertEqual(build, 2)
            XCTAssertEqual(routes, [.live])
            for _ in 0..<100 where session.isCommandInFlight { try await Task.sleep(for: .milliseconds(10)) }
            let saved = try store.load().pendingIntent
            if selected == 3 { try await captureCreate(controls, name: "native-create-pending-AX5", accessibility: true) }
            let replacement = LiveCreateControls(live: session, isSignedIn: true,
                                                 openRoute: { _ in }, roundCount: selected == 1 ? 5 : 1)
            replacement.create()
            XCTAssertEqual(try store.load().pendingIntent, saved, "a new picker cannot reconfigure an unresolved intent")
            session.leaveToHome()
            for _ in 0..<100 where session.isCommandInFlight { try await Task.sleep(for: .milliseconds(10)) }
        }
        let session = LiveMatchSession(service: nil, realtime: nil)
        var routes: [AppRoute] = []
        let signedOut = LiveCreateControls(live: session, isSignedIn: false, openRoute: { routes.append($0) })
        XCTAssertEqual(signedOut.roundCount, 3)
        signedOut.create()
        XCTAssertEqual(routes, [.account])
        XCTAssertNil(session.pendingIntent)
    }

    func testLaterStartIgnoresLobbyExpiryButRequiresCurrentRevealAndLiveRoster() throws {
        let snapshot = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        let afterExpiry = snapshot.match.expiresAt.addingTimeInterval(100)
        func canStart(_ value: LiveMatchSnapshot, pending: Bool = false, start: Bool = false) -> Bool {
            LiveMatchPresentation.canStart(snapshot: value, displayedServerTime: afterExpiry,
                                          isCommandInFlight: false, hasPendingIntent: pending, hasPendingStart: start)
        }
        XCTAssertTrue(canStart(snapshot))
        XCTAssertFalse(canStart(snapshot, pending: true))
        XCTAssertFalse(canStart(snapshot, start: true))
        for label in ["3-round-2-countdown", "3-round-2-playing", "3-round-3-reveal",
                      "deletion-active", "deletion-between", "deletion-active-revealed"] {
            XCTAssertFalse(canStart(try Phase4LiveFixtures.snapshot(label)), label)
        }
        var guest = try Phase4LiveFixtures.object("3-round-1-reveal")
        var members = try XCTUnwrap(guest["members"] as? [[String: Any]])
        members[0]["is_self"] = false
        members[1]["is_self"] = true
        guest["members"] = members
        XCTAssertFalse(canStart(try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(guest))))
        XCTAssertFalse(canStart(try Phase4LiveFixtures.snapshot("3-lobby"))) // creator alone
    }

    func testRoundOwnedDraftCannotHydrateFromOldRoundOrOtherMatch() throws {
        let snapshot = try Phase4LiveFixtures.snapshot("3-round-2-playing")
        let request = UUID()
        let current = LivePendingIntent.guess(matchID: snapshot.match.id, requestID: request,
                                              word: "STONE", roundNumber: 2, clientBuild: 2)
        let old = LivePendingIntent.guess(matchID: snapshot.match.id, requestID: request,
                                          word: "CRANE", roundNumber: 1, clientBuild: 2)
        let other = LivePendingIntent.guess(matchID: UUID(), requestID: request,
                                            word: "ADORE", roundNumber: 2, clientBuild: 2)
        XCTAssertEqual(LiveMatchPresentation.initialDraft(snapshot: snapshot, pending: current, draft: ""), "STONE")
        XCTAssertEqual(LiveMatchPresentation.initialDraft(snapshot: snapshot, pending: old, draft: "CRANE"), "")
        XCTAssertEqual(LiveMatchPresentation.initialDraft(snapshot: snapshot, pending: other, draft: "ADORE"), "")
        XCTAssertEqual(LiveMatchPresentation.initialDraft(snapshot: snapshot, pending: nil, draft: "NEW"), "NEW")
        XCTAssertTrue(LiveMatchPresentation.resolvedGuessClearsDraft(snapshot: snapshot, previous: current, current: nil, draft: ""))
        XCTAssertFalse(LiveMatchPresentation.resolvedGuessClearsDraft(snapshot: snapshot, previous: old, current: nil, draft: ""))
        XCTAssertFalse(LiveMatchPresentation.resolvedGuessClearsDraft(snapshot: snapshot, previous: other, current: nil, draft: ""))
        XCTAssertFalse(LiveMatchPresentation.resolvedGuessClearsDraft(snapshot: snapshot, previous: current, current: nil, draft: "STONE"),
                       "definitive rejection must keep its current-round draft")
        let prior = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
        XCTAssertNotEqual(LiveMatchPresentation.roundIdentity(snapshot), LiveMatchPresentation.roundIdentity(prior))
        XCTAssertEqual(LiveMatchPresentation.roundLabel(snapshot), "Round 2 of 3")
    }

    func testStandingsKeepSQLRanksWhenDisplayedTimesMatchAndNeverRecalculateTotals() throws {
        let final = try Phase4LiveFixtures.snapshot("3-round-3-reveal")
        let standings = try XCTUnwrap(final.standings)
        XCTAssertEqual(standings.players.map(\.placement), [1, 2])
        XCTAssertEqual(standings.players.map(\.totalSolveDurationMilliseconds), [4, 5])
        let sameMilliseconds = try XCTUnwrap(Phase4LiveFixtures.snapshot("1-round-1-reveal").standings)
        XCTAssertEqual(sameMilliseconds.players.map(\.totalSolveDurationMilliseconds), [1, 1])
        XCTAssertEqual(sameMilliseconds.players.map(\.placement), [1, 2])
        XCTAssertEqual(LiveMatchPresentation.standingsTitle(standings), "Final match standings")
        XCTAssertTrue(LiveMatchPresentation.standingSummary(standings.players[1]).contains("Place 2"))
        let tie = try XCTUnwrap(Phase4LiveFixtures.snapshot("3-final-tie").standings)
        XCTAssertEqual(tie.players.map(\.placement), [1, 1])
        let partial = try XCTUnwrap(Phase4LiveFixtures.snapshot("deletion-between").standings)
        XCTAssertFalse(partial.isFinal)
        XCTAssertEqual(LiveMatchPresentation.standingsTitle(partial), "Match standings so far")
        XCTAssertEqual(partial.throughRound, 1)
    }

    @MainActor
    func testPriorRevealIsDisplayOnlyAndNativeScreensRenderAtNormalAndAccessibilitySizes() async throws {
        for label in ["3-lobby", "3-round-1-countdown", "3-round-2-playing", "3-round-1-reveal", "3-round-2-reveal",
                      "1-round-1-reveal", "5-round-5-reveal", "3-final-tie", "deletion-between", "deletion-active"] {
            let snapshot: LiveMatchSnapshot
            if label == "3-lobby" {
                var object = try Phase4LiveFixtures.object(label)
                object["members"] = try Phase4LiveFixtures.object("3-round-1-countdown")["members"]
                snapshot = try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(object))
            } else { snapshot = try Phase4LiveFixtures.snapshot(label) }
            let pending: LivePendingIntent? = label == "3-final-tie"
                ? .guess(matchID: snapshot.match.id, requestID: UUID(), word: "CRANE", roundNumber: 1, clientBuild: 2) : nil
            let store = PresentationRecoveryStore(LiveRecoveryState(matchID: snapshot.match.id, pendingIntent: pending))
            let session = LiveMatchSession(service: PresentationService(snapshot), realtime: nil,
                                           storeFactory: { _ in store }, uptime: { 0 })
            session.backgrounded()
            session.changeAccount(to: UUID())
            session.resumeSavedMatch()
            session.foregrounded()
            for _ in 0..<100 where session.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(session.snapshot, snapshot, label)
            if label == "3-lobby" || label == "3-round-1-reveal" {
                session.startMatch()
                for _ in 0..<100 where session.isCommandInFlight || session.phase != .ready {
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertTrue(session.hasPendingStart)
                XCTAssertNil(session.lastError, "an unchanged ready snapshot must still show the saved Start")
                session.leaveToHome()
                session.resumeSavedMatch()
                for _ in 0..<100 where session.phase != .ready { try await Task.sleep(for: .milliseconds(10)) }
                XCTAssertTrue(session.hasPendingStart)
                XCTAssertTrue(session.canRetry)
            }
            if pending != nil {
                XCTAssertEqual(session.lastError, .server(.requestConflict))
                XCTAssertEqual(session.pendingIntent, pending)
            }
            defer { session.leaveToHome() }
            if label == "3-round-2-reveal" {
                session.selectReveal(number: 1)
                XCTAssertEqual(session.displayedReveal?.number, 1)
                XCTAssertEqual(session.snapshot?.round.number, 2)
                XCTAssertEqual(session.snapshot?.standings, snapshot.standings)
                session.selectReveal(number: 3)
                XCTAssertEqual(session.selectedRevealNumber, 1, "future reveals must not become selectable")
            }
            for accessibility in [false, true] {
                let view = NavigationStack {
                    LiveMatchFlowView(session: session, hapticsEnabled: false, highContrast: accessibility)
                }
                .tint(Color.raceIndigo)
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.legibilityWeight, accessibility ? .bold : .regular)
                let host = UIHostingController(rootView: view)
                host.traitOverrides.accessibilityContrast = accessibility ? .high : .normal
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(2500))
                host.view.layoutIfNeeded()
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                XCTAssertEqual(image.size.width, 393)
                let attachment = XCTAttachment(image: image)
                attachment.name = "native-\(label)-\(accessibility ? "AX5" : "normal")"
                attachment.lifetime = .keepAlways
                add(attachment)
                // Capture lower scroll content too: standings, saved actions and Home must remain reachable.
                let scrolls = descendants(host.view).compactMap { $0 as? UIScrollView }
                for (index, scroll) in scrolls.enumerated() where scroll.contentSize.height > scroll.bounds.height {
                    scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                    host.view.layoutIfNeeded()
                    let lower = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let attachment = XCTAttachment(image: lower)
                    attachment.name = "native-\(label)-\(accessibility ? "AX5" : "normal")-scroll-\(index)-bottom"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    private func captureCreate(_ controls: LiveCreateControls, name: String, accessibility: Bool = false) async throws {
        let host = UIHostingController(rootView: controls.padding(20).tint(Color.raceIndigo).background(Color.racePage)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: accessibility ? 650 : 300)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(150))
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private static func snapshot(
        status: LiveMatchStatus,
        roundState: LiveRoundState,
        selfSeat: Int
    ) -> LiveMatchSnapshot {
        let first = member(seat: 1, isSelf: selfSeat == 1)
        let second = member(seat: 2, isSelf: selfSeat == 2)
        let now = Date(timeIntervalSince1970: 1_000)
        let revealed = roundState == .revealed
        let firstRows = [guess(sequence: 1, word: "vivid")]
        let secondRows = [guess(sequence: 1, word: "adore"), guess(sequence: 2, word: "vivid")]
        return LiveMatchSnapshot(
            serverTime: now,
            match: LiveMatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                joinCode: "ABC234",
                creatorMemberID: first.id,
                status: status,
                expiresAt: now.addingTimeInterval(60),
                minimumClientBuild: 1
            ),
            members: [first, second],
            round: LiveRound(
                state: roundState,
                startsAt: roundState == .pending ? nil : now.addingTimeInterval(3),
                endsAt: roundState == .pending ? nil : now.addingTimeInterval(183),
                completedAt: revealed ? now : nil,
                answer: revealed ? "vivid" : nil,
                players: revealed ? [
                    player(member: first, rows: firstRows, placement: 1),
                    player(member: second, rows: secondRows, placement: 2),
                ] : []
            )
        )
    }

    private static func member(seat: Int, isSelf: Bool) -> LiveMatchMember {
        LiveMatchMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(seat)")!,
            seat: seat,
            displayName: "Player \(seat)",
            avatarSeed: "seed-\(seat)",
            isSelf: isSelf,
            isDeleted: false
        )
    }

    private static func guess(sequence: Int, word: String) -> LiveGuess {
        LiveGuess(
            sequence: sequence,
            word: word,
            feedback: [.correct, .correct, .correct, .correct, .correct],
            submittedAt: Date(timeIntervalSince1970: 1_000 + Double(sequence))
        )
    }

    private static func player(
        member: LiveMatchMember,
        rows: [LiveGuess],
        placement: Int
    ) -> LiveRoundPlayer {
        LiveRoundPlayer(
            memberID: member.id,
            state: .solved,
            acceptedGuessCount: rows.count,
            solveDurationMilliseconds: 500,
            efficiencyPoints: 7 - rows.count,
            placement: placement,
            board: rows
        )
    }
}

private final class PresentationRecoveryStore: LiveMatchRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: LiveRecoveryState
    init(_ state: LiveRecoveryState) { self.state = state }
    func load() throws -> LiveRecoveryState { lock.withLock { state } }
    func save(_ state: LiveRecoveryState) throws { lock.withLock { self.state = state } }
    func clear() throws { lock.withLock { state = LiveRecoveryState() } }
}

private struct PresentationService: LiveMatchServicing {
    let value: LiveMatchSnapshot
    init(_ value: LiveMatchSnapshot) { self.value = value }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot { value }
    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func joinMatch(code: String) async throws -> UUID { value.match.id }
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String,
                     clientBuild: Int) async throws -> LiveGuessReceipt { throw LiveMatchServiceError.server(.requestConflict) }
}
