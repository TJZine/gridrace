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
    func testEveryLiveStateMapsFromSessionFixturesAndRendersOnSE() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try await GameplayContainmentHost.establishOrientation(.portrait, in: scene)
        for scenario in RenderScenario.allCases {
            let fixture = try await makeScenario(scenario)
            let session = fixture.session
            defer { session.leaveToHome() }
            let retained = scenario == .invalidWord ? LiveMatchPresentation.errorMessage(.server(.invalidGuessFormat))
                : scenario == .rejectedWord ? LiveMatchPresentation.errorMessage(.server(.wordNotAccepted)) : nil
            let state = LiveMatchPresentation.State(session: session, isSignedIn: scenario != .signedOut, retainedError: retained)
            let mapped = LiveMatchPresentation.map(state)
            XCTAssertEqual(mapped.surface, scenario.surface, scenario.rawValue)
            let actions = mapped.controls + (mapped.notice?.controls ?? [])
                + (mapped.topNotice?.controls ?? []) + (mapped.savedNotice?.controls ?? [])
            XCTAssertEqual(actions.map { String(describing: $0.action) }.sorted(),
                scenario.actions.map { String(describing: $0) }.sorted(), scenario.rawValue)
            let notice = mapped.notice ?? mapped.savedNotice ?? mapped.topNotice
            XCTAssertEqual(notice?.body, scenario.body(snapshot: state.snapshot), scenario.rawValue)
            let needsAction = [.signedOut, .needsSignIn, .storageUnavailable, .failedJoin, .failedCreate,
                .failedCreateDecision, .topError, .savedStart, .entrySavedStart, .nextHostSavedStart,
                .savedRequestDecision, .guessDecision, .rateDecision, .connectionUnavailable].contains(scenario)
            XCTAssertEqual(notice?.requiresAction ?? false, needsAction, scenario.rawValue)
            if let title = scenario.title {
                XCTAssertEqual(mapped.notice?.title ?? mapped.savedNotice?.title ?? mapped.topNotice?.title,
                    title, scenario.rawValue)
            }
            if scenario == .failedJoin {
                XCTAssertFalse(session.canRetry, "failed Join cannot retry the old room")
                XCTAssertFalse(mapped.notice?.controls.contains { $0.action == .retry } ?? true)
                XCTAssertTrue(session.hasSavedMatch)
            }
            if scenario == .savedStart || scenario == .nextHostSavedStart {
                XCTAssertTrue(session.hasPendingStart)
                XCTAssertEqual(mapped.savedNotice?.controls, [.init(action: .retryStart, enabled: session.canRetry)])
            }
            if scenario == .entryPendingCreate {
                XCTAssertTrue(session.hasSavedMatch)
                XCTAssertEqual(mapped.surface, .entry)
                XCTAssertTrue(mapped.permits(.resume))
                XCTAssertFalse(mapped.permits(.create))
            }
            if scenario == .priorReveal {
                let canonical = session.snapshot
                XCTAssertEqual(session.displayedReveal?.number, 1)
                XCTAssertEqual(session.snapshot?.round.number, 2)
                XCTAssertEqual(mapped.priorRevealNotice?.title, "Round 1 reveal")
                session.selectReveal(number: 3)
                XCTAssertEqual(session.selectedRevealNumber, 1)
                XCTAssertEqual(session.snapshot, canonical, "history selection cannot mutate canonical standings or the current round")
            }
            if scenario == .hostAlone || scenario == .lobbyGuest || scenario == .expiredLobby {
                XCTAssertFalse(mapped.controls.contains { $0.action == .start })
            }
            if scenario == .hostTwo || scenario == .nextHost { XCTAssertTrue(mapped.permits(.start)) }
            if scenario == .incomplete {
                XCTAssertFalse(mapped.notice?.usesClaret ?? true)
                XCTAssertEqual(mapped.notice?.title, "Match incomplete")
                XCTAssertTrue(session.snapshot?.members.contains { $0.displayName == "Deleted Player" } ?? false)
            }
            if scenario == .rejectedWord || scenario == .invalidWord {
                XCTAssertEqual(session.guessDraft, "CRANE")
                XCTAssertNil(mapped.notice, "the keyboard stays available after definitive rejection")
                XCTAssertNotNil(mapped.inlineError)
            }
            if scenario == .finalSavedDecision {
                XCTAssertEqual(session.lastError, .server(.requestConflict))
                XCTAssertNotNil(session.pendingIntent, "a prior-round unresolved request survives final snapshots")
                XCTAssertEqual(mapped.savedNotice?.controls.map(\.action), [.retryRequest, .discardGuess])
            }
            if scenario == .guessDecision || scenario == .rateDecision {
                XCTAssertEqual(mapped.notice?.controls.map(\.action), [.retryRequest, .discardGuess])
            }
            for accessibility in [false, true] {
                let view = NavigationStack {
                    LiveMatchFlowView(session: session, hapticsEnabled: false, highContrast: accessibility,
                        isSignedIn: scenario != .signedOut)
                }
                .tint(Color.ink)
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.legibilityWeight, accessibility ? .bold : .regular)
                let host = UIHostingController(rootView: view)
                host.traitOverrides.accessibilityContrast = accessibility ? .high : .normal
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                if scenario == .invalidWord || scenario == .rejectedWord {
                    try await Task.sleep(for: .milliseconds(100))
                    session.submitGuess("CRANE")
                    try await settle(session)
                }
                try await Task.sleep(for: .milliseconds(2500))
                host.view.layoutIfNeeded()
                XCTAssertEqual(scene.interfaceOrientation, .portrait, "Live SE captures require an OS portrait scene")
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                func attach(_ suffix: String = "") {
                    let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "native-SE-\(scenario.rawValue)-\(accessibility ? "AX5" : "normal")\(suffix)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                attach()
                // Only vertical scrolls: the board and keyboard own horizontal AX scrolling.
                let scrolls = descendants(host.view).compactMap { $0 as? UIScrollView }
                for (index, scroll) in scrolls.enumerated() where scroll.contentSize.height > scroll.bounds.height + 1 {
                    scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                    host.view.layoutIfNeeded()
                    attach("-scroll-\(index)-bottom")
                }
            }
            await fixture.service.releaseDelays()
            session.leaveToHome()
            for _ in 0..<100 where session.isCommandInFlight { try await Task.sleep(for: .milliseconds(10)) }
        }
    }

    @MainActor
    func testLiveGameplayContainmentAndAccessibilityReachability() async throws {
        for accessibility in [false, true] {
            for landscape in accessibility ? [false] : [false, true] {
                for scenario in [RenderScenario.playing, .rejectedWord, .guessDecision, .solved] {
                    let fixture = try await makeScenario(scenario)
                    defer { fixture.session.leaveToHome() }
                    try await GameplayContainmentHost.withHost(
                        GameplayRouteView(.live) {
                            LiveMatchFlowView(session: fixture.session, hapticsEnabled: false,
                                              highContrast: false, isSignedIn: true)
                        }, landscape: landscape, accessibility: accessibility) { hosted in
                        if scenario == .rejectedWord {
                            fixture.session.submitGuess("CRANE")
                            try await settle(fixture.session)
                            try await hosted.settle()
                        }
                        let presentation = LiveMatchPresentation.map(.init(session: fixture.session))
                        let notices = scenario == .rejectedWord
                            ? [try XCTUnwrap(LiveMatchPresentation.errorMessage(.server(.wordNotAccepted)))]
                            : presentation.notice.map { [$0.body] } ?? []
                        let actions = scenario == .guessDecision ? ["Retry saved request", "Discard saved request"] : []
                        try hosted.assertGameplay(in: self, name: "live-\(scenario.rawValue)", notices: notices,
                                                  expectsKeyboard: presentation.notice == nil, actions: actions,
                                                  opponents: try XCTUnwrap(fixture.session.snapshot).members.filter { !$0.isSelf }.count,
                                                  hasTimer: true)
                    }
                }
            }
        }
    }

    @MainActor
    func testPresentationConsumesStartCapabilityAndPreservesStoragePrecedence() async throws {
        let fixture = try await makeScenario(.hostTwo)
        defer { fixture.session.leaveToHome() }
        var state = LiveMatchPresentation.State(session: fixture.session)
        state.canStart = false
        XCTAssertFalse(LiveMatchPresentation.map(state).permits(.start))
        state.canStart = true
        XCTAssertTrue(LiveMatchPresentation.map(state).permits(.start))
        state.phase = .storageUnavailable
        state.canRetryRecoveryStorage = false
        state.canDiscardRecovery = false
        XCTAssertEqual(LiveMatchPresentation.map(state).notice?.controls.map(\.action), [.account])
        state.canRetryRecoveryStorage = true
        state.canDiscardRecovery = true
        XCTAssertEqual(LiveMatchPresentation.map(state).notice?.controls.map(\.action), [.retryStorage, .discardRecovery, .account])
        state.phase = .ready
        state.hasPendingStart = true
        state.canRetry = false
        state.pendingIntent = .create(requestID: UUID(), roundCount: 3, clientBuild: 2)
        state.error = .server(.requestConflict)
        let start = LiveMatchPresentation.map(state)
        XCTAssertNil(start.topNotice)
        XCTAssertEqual(start.savedNotice?.title, "Round didn't start yet")
        XCTAssertEqual(start.savedNotice?.controls, [.init(action: .retryStart, enabled: false)])
        state.hasPendingStart = false
        XCTAssertEqual(LiveMatchPresentation.map(state).savedNotice?.controls,
            [.init(action: .retryRequest, enabled: false), .init(action: .discardCreate)])
        state.snapshot = nil
        state.phase = .inactive
        state.hasSavedMatch = true
        state.joinCode = "ABC234"
        let entry = LiveMatchPresentation.map(state)
        XCTAssertTrue(entry.permits(.resume))
        XCTAssertTrue(entry.permits(.join), "Join preserves its existing presentation gate; the session still owns intent safety")
        XCTAssertFalse(entry.permits(.create))
        state.isCommandInFlight = true
        XCTAssertFalse(LiveMatchPresentation.map(state).permits(.join))
    }

    private enum RenderScenario: String, CaseIterable {
        case signedOut, entry, entryPendingCreate, entrySavedStart, needsSignIn, storageUnavailable, recovering
        case failedJoin, failedCreate, failedCreateDecision, topError, savedStart, savedRequestDecision
        case hostAlone, hostTwo, lobbyGuest, expiredLobby, countdown, deletionCountdown, deletionPlaying
        case playing, solved, failed, timedOut, forfeited, terminalRecovering, terminalUnavailable
        case sendingGuess, guessDecision, rateDecision, connectionRecovering, connectionUnavailable
        case deadline, invalidWord, rejectedWord, revealUnavailable, priorReveal, nextHost, nextGuest
        case final, finalFive, finalTie, finalSavedDecision, nextHostSavedStart, incomplete

        var surface: LiveMatchPresentation.Surface {
            switch self {
            case .entry, .entryPendingCreate, .entrySavedStart: .entry
            case .hostAlone, .hostTwo, .lobbyGuest, .expiredLobby, .savedStart, .savedRequestDecision, .topError: .lobby
            case .countdown, .deletionCountdown: .countdown
            case .playing, .solved, .failed, .timedOut, .forfeited, .terminalRecovering, .terminalUnavailable,
                 .sendingGuess, .guessDecision, .rateDecision, .connectionRecovering, .connectionUnavailable,
                 .deadline, .invalidWord, .rejectedWord, .deletionPlaying: .round
            case .revealUnavailable, .priorReveal, .nextHost, .nextGuest, .nextHostSavedStart,
                 .final, .finalFive, .finalTie, .finalSavedDecision, .incomplete: .reveal
            default: .notice
            }
        }
        var actions: [LiveMatchPresentation.Action] {
            switch self {
            case .signedOut: [.home, .account]
            case .entry: [.home, .create, .join]
            case .entryPendingCreate: [.home, .resume, .create, .join]
            case .entrySavedStart: [.home, .resume, .create, .join, .retryStart]
            case .needsSignIn: [.home, .backToRace, .account]
            case .storageUnavailable: [.home, .retryStorage, .discardRecovery, .account]
            case .failedJoin: [.home, .backToRace, .account]
            case .failedCreate: [.home, .retry, .discardCreate, .backToRace, .account]
            case .failedCreateDecision: [.home, .retryRequest, .discardCreate, .backToRace, .account]
            case .hostAlone, .lobbyGuest: [.home, .copyCode, .shareCode]
            case .hostTwo: [.home, .copyCode, .shareCode, .start]
            case .savedStart: [.home, .copyCode, .shareCode, .start, .retryStart]
            case .savedRequestDecision: [.home, .copyCode, .shareCode, .start, .retryRequest, .discardGuess]
            case .topError: [.home, .copyCode, .shareCode, .start, .retry]
            case .guessDecision, .rateDecision: [.home, .retryRequest, .discardGuess]
            case .connectionUnavailable, .terminalUnavailable: [.home, .retry]
            case .priorReveal: [.home, .selectReveal, .start]
            case .nextHost: [.home, .start]
            case .finalTie, .finalFive: [.home, .selectReveal]
            case .finalSavedDecision: [.home, .selectReveal, .retryRequest, .discardGuess]
            case .nextHostSavedStart: [.home, .start, .retryStart]
            default: [.home]
            }
        }
        func body(snapshot: LiveMatchSnapshot?) -> String? {
            let opponent = snapshot?.members.first { !$0.isSelf }?.displayName ?? "player two"
            switch self {
            case .signedOut: return "Live races need a player name. Daily stays open without an account."
            case .needsSignIn: return "Your race is saved on this device. Go back to the race to try again; signing out removes it."
            case .storageUnavailable: return "Saved race data on this device couldn't be read or cleared."
            case .recovering: return "Hang tight. This only takes a moment."
            case .failedJoin: return "This room already has two players."
            case .failedCreate: return "The live match is unavailable. Check your connection and try again."
            case .failedCreateDecision, .guessDecision, .savedRequestDecision: return "Retry or discard it."
            case .rateDecision: return "Try again in a moment."
            case .topError: return ""
            case .savedStart, .entrySavedStart, .nextHostSavedStart: return "Retry starts the same round."
            case .hostAlone: return "Share the code to invite them."
            case .lobbyGuest: return "The host starts each round."
            case .expiredLobby: return "It expired before the race started."
            case .countdown, .deletionCountdown: return "Starts on the server clock. Leaving the app won't pause it."
            case .solved, .failed, .timedOut, .forfeited, .terminalRecovering, .terminalUnavailable: return "Waiting for \(opponent)"
            case .sendingGuess: return "Typing is locked until it's confirmed."
            case .connectionRecovering, .connectionUnavailable: return "Your board is saved. Typing resumes when you're back."
            case .deadline: return "Getting the final result for this round."
            case .revealUnavailable: return "The full reveal hasn't arrived yet."
            case .nextGuest: return "They'll start round 2 of 3."
            case .final, .finalFive, .finalTie, .finalSavedDecision: return "Final match standings"
            case .incomplete: return "Your opponent left GridRace after round 1. The rounds you played are saved; round 2 won't be played."
            default: return nil
            }
        }
        var title: String? {
            switch self {
            case .signedOut: "Sign in to race"
            case .needsSignIn: "Your sign-in expired"
            case .storageUnavailable: "Couldn't open your saved race"
            case .recovering: "Connecting to your race"
            case .failedJoin, .failedCreate, .failedCreateDecision: "Race unavailable"
            case .hostAlone: "Waiting for player two"
            case .expiredLobby: "This room closed"
            case .savedStart, .entrySavedStart, .nextHostSavedStart: "Round didn't start yet"
            case .solved, .terminalRecovering, .terminalUnavailable: "Solved in 2"
            case .failed: "Out of guesses"
            case .timedOut, .deadline: "Time's up"
            case .forfeited: "Round forfeited"
            case .sendingGuess: "Sending your guess"
            case .guessDecision, .rateDecision: "Your guess needs a decision"
            case .savedRequestDecision: "Your saved request needs a decision"
            case .connectionRecovering: "Reconnecting"
            case .connectionUnavailable: "Connection lost"
            case .revealUnavailable: "Reveal on its way"
            case .final, .finalFive: "You won"
            case .finalTie, .finalSavedDecision: "Tied"
            case .incomplete: "Match incomplete"
            case .lobbyGuest, .nextGuest: "Waiting for Player dae45d"
            case .countdown, .deletionCountdown: "Round 1 of 3"
            case .topError: "This live match needs a newer compatible response. Try again."
            default: nil
            }
        }
    }

    @MainActor
    private func makeScenario(_ scenario: RenderScenario) async throws -> (session: LiveMatchSession, service: RenderService) {
        let label: String = switch scenario.surface {
        case .lobby: "3-lobby"
        case .countdown: scenario == .deletionCountdown ? "deletion-active" : "3-round-1-countdown"
        case .round: scenario == .deletionPlaying ? "deletion-active" : "3-round-1-playing"
        case .reveal:
            switch scenario {
            case .final: "1-round-1-reveal"
            case .finalTie, .finalSavedDecision: "3-final-tie"
            case .finalFive: "5-round-5-reveal"
            case .incomplete: "deletion-between"
            case .priorReveal: "3-round-2-reveal"
            default: "3-round-1-reveal"
            }
        default: "3-lobby"
        }
        var snapshot = try Phase4LiveFixtures.snapshot(label)
        if [.hostTwo, .lobbyGuest, .savedStart, .entrySavedStart, .topError, .savedRequestDecision].contains(scenario) {
            var object = try Phase4LiveFixtures.object(label)
            object["members"] = try Phase4LiveFixtures.object("3-round-1-countdown")["members"]
            snapshot = try SupabaseLiveMatchService.decodeSnapshot(Phase4LiveFixtures.envelope(object))
        }
        if scenario == .lobbyGuest || scenario == .nextGuest {
            snapshot = replacing(snapshot, members: snapshot.members.map {
                LiveMatchMember(id: $0.id, seat: $0.seat, displayName: $0.displayName, avatarSeed: $0.avatarSeed,
                    isSelf: !$0.isSelf, isDeleted: $0.isDeleted)
            })
        }
        if scenario == .expiredLobby { snapshot = replacing(snapshot, time: snapshot.match.expiresAt) }
        if [.solved, .failed, .timedOut, .forfeited, .terminalRecovering, .terminalUnavailable].contains(scenario) {
            let own = try XCTUnwrap(snapshot.members.first(where: \.isSelf))
            let state: LivePlayerState = switch scenario {
            case .failed: .failed
            case .timedOut: .timedOut
            case .forfeited: .forfeited
            default: .solved
            }
            let canonical = try Phase4LiveFixtures.snapshot("3-round-1-reveal")
            let solvedRows = try XCTUnwrap(canonical.round.players.first { $0.memberID == own.id }?.board)
            let incorrect = try XCTUnwrap(solvedRows.first)
            let count = state == .failed ? 6 : 2
            let rows = state == .solved ? solvedRows : (1...count).map { sequence in
                LiveGuess(sequence: sequence, word: incorrect.word, feedback: incorrect.feedback,
                    submittedAt: (snapshot.round.startsAt ?? snapshot.serverTime)
                        .addingTimeInterval(Double(sequence) / 1000))
            }
            let players = snapshot.round.players.map { player in
                player.memberID != own.id ? player : LiveRoundPlayer(memberID: own.id, state: state,
                    acceptedGuessCount: rows.count, solveDurationMilliseconds: state == .solved ? 500 : nil,
                    efficiencyPoints: nil, placement: nil, board: rows)
            }
            snapshot = replacing(snapshot, round: LiveRound(state: .playing, startsAt: snapshot.round.startsAt,
                endsAt: snapshot.round.endsAt, completedAt: nil, answer: nil, players: players))
        }
        if scenario == .deletionPlaying {
            snapshot = replacing(snapshot, time: try XCTUnwrap(snapshot.round.startsAt),
                round: LiveRound(state: .playing, startsAt: snapshot.round.startsAt, endsAt: snapshot.round.endsAt,
                    completedAt: nil, answer: nil, players: snapshot.round.players))
        }
        if scenario == .revealUnavailable {
            snapshot = replacing(snapshot, round: LiveRound(state: .revealed, startsAt: snapshot.round.startsAt,
                endsAt: snapshot.round.endsAt, completedAt: snapshot.round.completedAt, answer: nil,
                players: snapshot.round.players))
        }
        if scenario == .deadline { snapshot = replacing(snapshot, time: try XCTUnwrap(snapshot.round.endsAt)) }
        let service = RenderService(snapshot)
        let empty = [.signedOut, .entry, .entryPendingCreate, .failedCreate, .failedCreateDecision].contains(scenario)
        let pending: LivePendingIntent? = scenario == .savedRequestDecision || scenario == .finalSavedDecision
            ? .guess(matchID: snapshot.match.id, requestID: UUID(), word: "CRANE", roundNumber: 1, clientBuild: 2) : nil
        let store = PresentationRecoveryStore(LiveRecoveryState(matchID: empty ? nil : snapshot.match.id, pendingIntent: pending))
        let realtime = RenderRealtime()
        let session = LiveMatchSession(service: service, realtime: realtime, storeFactory: { _ in
            if scenario == .storageUnavailable { throw LiveMatchServiceError.unavailable }
            return store
        }, timing: LiveMatchSessionTiming(requestTimeout: .seconds(60), staleAfter: .seconds(3600),
            retryBackoff: [.seconds(3600)]), uptime: { 0 })
        if scenario == .signedOut { return (session, service) }
        session.changeAccount(to: UUID())
        if scenario == .storageUnavailable || scenario == .entry { return (session, service) }
        if scenario == .entryPendingCreate {
            await service.configure(commandDelay: true)
            session.createMatch()
            session.leaveToHome()
            return (session, service)
        }
        if scenario == .failedCreate || scenario == .failedCreateDecision {
            if scenario == .failedCreateDecision { await service.configure(createError: .server(.requestConflict)) }
            session.createMatch()
            try await settle(session)
            return (session, service)
        }
        if scenario == .failedJoin {
            session.joinMatch(code: "ABC234")
            try await settle(session)
            return (session, service)
        }
        if scenario == .recovering { await service.configure(snapshotDelay: true) }
        if scenario == .needsSignIn { await service.configure(snapshotError: .server(.notAuthenticated)) }
        session.resumeSavedMatch()
        if scenario == .recovering { return (session, service) }
        try await settle(session)
        if scenario == .needsSignIn { return (session, service) }
        XCTAssertEqual(session.snapshot, snapshot, scenario.rawValue)
        if scenario == .savedStart || scenario == .entrySavedStart || scenario == .nextHostSavedStart {
            session.startMatch()
            try await settle(session)
            XCTAssertTrue(session.hasPendingStart)
            session.leaveToHome()
            if scenario == .entrySavedStart { return (session, service) }
            session.resumeSavedMatch()
            try await settle(session)
        }
        if scenario == .priorReveal { session.selectReveal(number: 1) }
        if [.topError, .connectionUnavailable, .terminalUnavailable, .connectionRecovering, .terminalRecovering].contains(scenario) {
            let recovering = scenario == .connectionRecovering || scenario == .terminalRecovering
            await service.configure(snapshotError: recovering ? nil : .invalidResponse, snapshotDelay: recovering)
            realtime.send(recovering ? .disconnected : .signal)
            if recovering { try await Task.sleep(for: .milliseconds(30)) }
            else { try await settle(session) }
        }
        if [.sendingGuess, .guessDecision, .rateDecision, .rejectedWord, .invalidWord].contains(scenario) {
            let error: LiveMatchServiceError = switch scenario {
            case .rateDecision: .server(.rateLimited)
            case .rejectedWord: .server(.wordNotAccepted)
            case .invalidWord: .server(.invalidGuessFormat)
            default: .server(.requestConflict)
            }
            await service.configure(guessError: error, commandDelay: scenario == .sendingGuess)
            session.submitGuess("CRANE")
            if scenario != .sendingGuess { try await settle(session) }
        }
        return (session, service)
    }

    @MainActor
    private func settle(_ session: LiveMatchSession) async throws {
        for _ in 0..<200 where session.isCommandInFlight || session.phase == .recovering {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(30))
    }

    private func replacing(_ snapshot: LiveMatchSnapshot, time: Date? = nil,
        members: [LiveMatchMember]? = nil, round: LiveRound? = nil) -> LiveMatchSnapshot {
        LiveMatchSnapshot(serverTime: time ?? snapshot.serverTime, match: snapshot.match,
            members: members ?? snapshot.members, round: round ?? snapshot.round, revision: snapshot.revision,
            revealedRounds: snapshot.revealedRounds, standings: snapshot.standings)
    }

    @MainActor
    private func captureCreate(_ controls: LiveCreateControls, name: String, accessibility: Bool = false) async throws {
        let host = UIHostingController(rootView: controls.padding(20).tint(Color.ink).background(Color.page)
            .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try await GameplayContainmentHost.establishOrientation(.portrait, in: scene)
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

/// Deterministic in-process command/snapshot transport for faithful native screens.
/// Delays are cancellable so each fixture releases every session task.
private actor RenderService: LiveMatchServicing {
    let value: LiveMatchSnapshot
    var snapshotError: LiveMatchServiceError?
    var snapshotDelay = false
    var guessError: LiveMatchServiceError = .server(.requestConflict)
    var createError: LiveMatchServiceError = .unavailable
    var commandDelay = false
    init(_ value: LiveMatchSnapshot) { self.value = value }
    func configure(snapshotError: LiveMatchServiceError? = nil, snapshotDelay: Bool = false,
        guessError: LiveMatchServiceError = .server(.requestConflict), commandDelay: Bool = false,
        createError: LiveMatchServiceError = .unavailable) {
        self.snapshotError = snapshotError
        self.snapshotDelay = snapshotDelay
        self.guessError = guessError
        self.createError = createError
        self.commandDelay = commandDelay
    }
    func releaseDelays() { snapshotDelay = false; commandDelay = false }
    func snapshot(matchID: UUID) async throws -> LiveMatchSnapshot {
        while snapshotDelay { try await Task.sleep(for: .milliseconds(20)) }
        if let snapshotError { throw snapshotError }
        return value
    }
    func createMatch(requestID: UUID, roundCount: Int, clientBuild: Int) async throws -> UUID {
        while commandDelay { try await Task.sleep(for: .milliseconds(20)) }
        throw createError
    }
    func joinMatch(code: String) async throws -> UUID { throw LiveMatchServiceError.server(.roomFull) }
    func startMatch(id: UUID, roundNumber: Int) async throws -> UUID { throw LiveMatchServiceError.unavailable }
    func submitGuess(matchID: UUID, roundNumber: Int, requestID: UUID, guess: String,
        clientBuild: Int) async throws -> LiveGuessReceipt {
        while commandDelay { try await Task.sleep(for: .milliseconds(20)) }
        throw guessError
    }
}

private final class RenderRealtime: LiveMatchRealtimeServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<LiveMatchRealtimeEvent, Error>.Continuation?
    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.yield(.ready)
        }
    }
    func send(_ event: LiveMatchRealtimeEvent) { lock.withLock { continuation?.yield(event) } }
}
