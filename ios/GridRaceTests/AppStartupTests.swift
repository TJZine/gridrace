import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import GridRace

/// Exercises the composition and recovery actions consumed directly by AppRootView.
/// Platform interaction/VoiceOver acceptance remains separate from this boundary.
@MainActor
final class AppStartupTests: XCTestCase {
    func testBundleFailureStopsBeforeStorageAndOffersOnlyRetry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var bundleUnavailable = true
        var storeAttempts = 0
        let startup = AppStartupModel(
            loadPacks: {
                if bundleUnavailable { throw DailyClassicError.missingWordPack }
                return try self.packs()
            },
            makeStore: { storeAttempts += 1; return fixture.store },
            makeApp: makeApp
        )
        startup.loadApp()
        guard case .bundledData? = startup.loadFailure else { return XCTFail("Expected bundle recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(storeAttempts, 0)
        startup.perform(.resetGuest)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
        bundleUnavailable = false
        startup.perform(.retry)
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(storeAttempts, 1)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original)
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testConstructionFailureRetainsStorageDiagnosisAndRetryRecoversWithoutReset() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var unavailable = true
        var storeAttempts = 0
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: {
                storeAttempts += 1
                if unavailable { throw CocoaError(.fileReadNoPermission) }
                return fixture.store
            },
            makeApp: makeApp
        )
        startup.loadApp()
        guard case .storageUnavailable? = startup.loadFailure else { return XCTFail("Expected storage recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(storeAttempts, 1, "Construction occurs once per attempt")
        startup.perform(.resetGuest)
        XCTAssertEqual(storeAttempts, 1)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
        unavailable = false
        startup.perform(.retry)
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(storeAttempts, 2)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original)
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testPuzzleUnavailableRetainsBundleClassificationAndCannotResetConstructedStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: { fixture.store },
            makeApp: { _, _, _ in throw DailyClassicError.puzzleUnavailable }
        )
        startup.loadApp()
        guard case .bundledData? = startup.loadFailure else { return XCTFail("Expected bundle recovery") }
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        startup.perform(.resetGuest)
        XCTAssertEqual(try fixture.snapshot(), fixture.original)
    }

    func testCorruptHistoryOrUnreadableProgressRetryPreservesFilesAndScopedResetRecovers() throws {
        for filename in ["daily-progress-v1.json", "daily-history-v1.json"] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            if filename == "daily-progress-v1.json" {
                let progress = fixture.root.appending(path: filename, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: progress, withIntermediateDirectories: true)
                try Data("unreadable as a progress file".utf8).write(to: progress.appending(path: "fixture.txt"))
            } else {
                let puzzle = try DailyPuzzleSchedule.puzzle(at: Date(), in: packs().daily)
                try fixture.store.save(DailyClassicProgress(puzzle: puzzle, hardModeEnabled: false))
                try Data("invalid saved data".utf8).write(to: fixture.root.appending(path: filename))
            }
            let before = try fixture.snapshot()
            var storeAttempts = 0
            let startup = AppStartupModel(
                loadPacks: packs,
                makeStore: { storeAttempts += 1; return fixture.store },
                makeApp: makeApp
            )
            startup.loadApp()
            guard case .savedData(let retained)? = startup.loadFailure else { return XCTFail("Expected guest recovery for \(filename)") }
            XCTAssertEqual(retained.directory, fixture.root)
            XCTAssertEqual(startup.loadFailure?.actions, [.retry, .resetGuest])
            XCTAssertEqual(storeAttempts, 1)
            startup.perform(.retry)
            XCTAssertNil(startup.appModel)
            XCTAssertEqual(startup.loadFailure?.actions, [.retry, .resetGuest])
            XCTAssertEqual(try fixture.snapshot(), before, "Retry must preserve even unreadable guest files")
            startup.perform(.resetGuest)
            XCTAssertNotNil(startup.appModel)
            XCTAssertNil(startup.loadFailure)
            let after = try fixture.snapshot()
            XCTAssertEqual(after.filter { $0.key != "daily-progress-v1.json" },
                           before.filter { $0.key != "daily-history-v1.json" && !$0.key.hasPrefix("daily-progress-v1.json") })
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appending(path: "daily-history-v1.json").path))
            XCTAssertEqual(try fixture.store.loadHistory(), DailyClassicHistory())
            try assertFreshProgress(startup, fixture: fixture)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.path))
            // A stale reset intent after recovery cannot clear subsequently saved data.
            try fixture.store.save(DailyClassicHistory())
            let recovered = try fixture.snapshot()
            startup.perform(.resetGuest)
            XCTAssertEqual(try fixture.snapshot(), recovered)
        }
    }

    func testInvalidProgressUsesExistingRepairWithoutExposingRootReset() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("invalid saved progress".utf8).write(to: fixture.root.appending(path: "daily-progress-v1.json"))
        let startup = AppStartupModel(loadPacks: packs, makeStore: { fixture.store }, makeApp: makeApp)
        startup.loadApp()
        XCTAssertNotNil(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" }, fixture.original,
                       "Existing invalid-progress repair preserves history and accounts")
        try assertFreshProgress(startup, fixture: fixture)
    }

    func testConstructionRetryPreservesExistingNonemptyProgress() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try packs().daily
        let now = Date()
        let puzzle = try DailyPuzzleSchedule.puzzle(at: now, in: pack)
        var game = DailyClassicGame(puzzle: puzzle, acceptedWords: Set(pack.acceptedGuesses))
        let word = try XCTUnwrap(pack.acceptedGuesses.first { $0 != puzzle.answer })
        for letter in word { game.type(letter) }
        XCTAssertNotNil(game.submit(at: now).guess)
        try fixture.store.save(game.progress)
        let before = try fixture.snapshot()
        var unavailable = true
        let startup = AppStartupModel(
            loadPacks: packs,
            makeStore: {
                if unavailable { throw CocoaError(.fileReadNoPermission) }
                return fixture.store
            },
            makeApp: makeApp
        )
        startup.loadApp()
        XCTAssertEqual(startup.loadFailure?.actions, [.retry])
        XCTAssertEqual(try fixture.snapshot(), before)
        unavailable = false
        startup.perform(.retry)
        let app = try XCTUnwrap(startup.appModel)
        XCTAssertNil(startup.loadFailure)
        XCTAssertEqual(app.daily.game.progress, game.progress)
        XCTAssertEqual(try fixture.store.loadProgress(), game.progress)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key != "daily-progress-v1.json" },
                       before.filter { $0.key != "daily-progress-v1.json" })
    }

    func testRecoveryMessagesPreserveFailureSpecificConsequencesAndActions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let cases: [(AppStartupModel.LoadFailure, String, [AppStartupModel.RecoveryAction])] = [
            (
                .bundledData,
                "The bundled puzzle data is unavailable. Reinstall or update GridRace.",
                [.retry]
            ),
            (
                .storageUnavailable,
                "Guest Daily Classic storage is unavailable. Try again to access your saved data.",
                [.retry]
            ),
            (
                .savedData(fixture.store),
                "Your guest Daily Classic data could not be read. You can retry or explicitly reset guest Daily progress and history. Signed-in account data is preserved.",
                [.retry, .resetGuest]
            )
        ]

        for (failure, message, actions) in cases {
            XCTAssertEqual(failure.message, message)
            XCTAssertEqual(failure.actions, actions)
        }
    }

    func testRecoveryRendersFullDiagnosticsAndReachesActionsThroughScrolling() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let failures: [AppStartupModel.LoadFailure] = [
            .bundledData,
            .storageUnavailable,
            .savedData(fixture.store)
        ]

        for (failureIndex, failure) in failures.enumerated() {
            for accessibility in [false, true] {
                for landscape in [false, true] {
                    try await GameplayContainmentHost.withHost(
                        StartupRecoveryView(loadFailure: failure, perform: { _ in }),
                        landscape: landscape,
                        accessibility: accessibility
                    ) { hosted in
                        let constrainedFrame = landscape
                            ? CGRect(x: 0, y: 0, width: 667, height: 375)
                            : CGRect(x: 0, y: 0, width: 375, height: 667)
                        let largerFrame = hosted.window.windowScene?.coordinateSpace.bounds ?? constrainedFrame

                        for frame in [constrainedFrame, largerFrame] {
                            hosted.window.frame = frame
                            hosted.host.view.frame = hosted.window.bounds
                            hosted.window.layoutIfNeeded()
                            hosted.host.view.layoutIfNeeded()
                            try await Task.sleep(for: .milliseconds(100))

                            let caseID = "failure-\(failureIndex)-\(accessibility ? "AX5" : "normal")-\(landscape ? "landscape" : "portrait")-\(Int(frame.width))x\(Int(frame.height))"
                            let expected = [failure.message] + failure.actions.map(\.title)
                            var reached = Set<String>()
                            var measuredContentBounds: CGRect?
                            var messageContentFrame: CGRect?
                            var messageVisibleIntervals: [ClosedRange<CGFloat>] = []
                            var messageWasHorizontallyClipped = false

                            func normalized(_ value: String) -> String {
                                value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                            }

                            @MainActor func observe(contentOffset: CGFloat) {
                                let elements = hosted.elements()
                                for expectedLabel in expected {
                                    let expectedText = normalized(expectedLabel)
                                    guard let element = elements.first(where: {
                                        normalized($0.label).contains(expectedText)
                                    }) else { continue }

                                    let contentFrame = element.frame.offsetBy(dx: 0, dy: contentOffset)
                                    measuredContentBounds = measuredContentBounds.map {
                                        $0.union(contentFrame)
                                    } ?? contentFrame

                                    if expectedLabel == failure.message {
                                        messageContentFrame = messageContentFrame ?? contentFrame
                                        var visibleFrame = element.frame.intersection(hosted.viewport)
                                        for clip in element.clips {
                                            visibleFrame = visibleFrame.intersection(clip)
                                        }
                                        guard !visibleFrame.isNull, !visibleFrame.isEmpty else { continue }
                                        if visibleFrame.width + 1 < element.frame.width {
                                            messageWasHorizontallyClipped = true
                                        }
                                        messageVisibleIntervals.append(
                                            (visibleFrame.minY + contentOffset)...(visibleFrame.maxY + contentOffset)
                                        )
                                        if hosted.isVisible(element) {
                                            reached.insert(expectedLabel)
                                        }
                                    } else if hosted.isVisible(element) {
                                        reached.insert(expectedLabel)
                                    }
                                }
                            }

                            @MainActor func attachRender(_ position: String) {
                                let image = UIGraphicsImageRenderer(bounds: hosted.host.view.bounds).image { _ in
                                    hosted.host.view.drawHierarchy(in: hosted.host.view.bounds, afterScreenUpdates: true)
                                }
                                let attachment = XCTAttachment(image: image)
                                attachment.name = "recovery-f\(failureIndex)-\(accessibility ? "AX5" : "normal")-\(landscape ? "landscape" : "portrait")-\(Int(frame.width))x\(Int(frame.height))-\(position)"
                                attachment.lifetime = .keepAlways
                                self.add(attachment)
                            }

                            let scrolls = descendants(of: hosted.host.view).compactMap { $0 as? UIScrollView }
                            let verticalScrolls = scrolls.filter { $0.contentSize.height > $0.bounds.height + 1 }
                            // Each frame starts at the top; the previous frame's sweep
                            // must not contaminate initial screenshots or content coordinates.
                            for scroll in verticalScrolls {
                                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                                                              y: -scroll.adjustedContentInset.top), animated: false)
                            }
                            hosted.host.view.layoutIfNeeded()
                            observe(contentOffset: verticalScrolls.first?.contentOffset.y ?? 0)
                            attachRender("initial")
                            if accessibility, frame == constrainedFrame, failure.actions.count > 1 {
                                XCTAssertFalse(verticalScrolls.isEmpty,
                                               "\(caseID): AX5 constrained recovery must provide a usable vertical scroll path")
                            }
                            // A complete AX label can survive a visually clipped Text. Measure
                            // the rendered required elements in scroll-content coordinates and
                            // prove that the full description is covered without vertical gaps.
                            if let scroll = verticalScrolls.first {
                                let minimum = -scroll.adjustedContentInset.top
                                let maximum = max(minimum,
                                                  scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                                let steps = max(1, Int(ceil((maximum - minimum) / max(1, scroll.bounds.height / 3))))
                                for step in 0...steps {
                                    let offset = minimum + (maximum - minimum) * CGFloat(step) / CGFloat(steps)
                                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                                    hosted.host.view.layoutIfNeeded()
                                    observe(contentOffset: scroll.contentOffset.y)
                                    if accessibility, failure.actions.count > 1, frame == constrainedFrame {
                                        attachRender("scroll-\(step)")
                                    }
                                }
                            }

                            if let scroll = verticalScrolls.first, let measuredContentBounds {
                                XCTAssertLessThanOrEqual(
                                    measuredContentBounds.height,
                                    scroll.contentSize.height + 2,
                                    "\(caseID): recovery diagnostic and actions must occupy measured, unclipped scroll content"
                                )
                            }

                            XCTAssertFalse(messageWasHorizontallyClipped,
                                           "\(caseID): recovery diagnostic must remain horizontally contained")
                            if let messageContentFrame {
                                XCTAssertGreaterThanOrEqual(
                                    messageContentFrame.minX,
                                    hosted.viewport.minX - 1,
                                    "\(caseID): recovery diagnostic starts inside the usable viewport"
                                )
                                XCTAssertLessThanOrEqual(
                                    messageContentFrame.maxX,
                                    hosted.viewport.maxX + 1,
                                    "\(caseID): recovery diagnostic ends inside the usable viewport"
                                )

                                let intervals = messageVisibleIntervals.sorted { $0.lowerBound < $1.lowerBound }
                                var coveredThrough = messageContentFrame.minY
                                for interval in intervals {
                                    guard interval.upperBound >= messageContentFrame.minY,
                                          interval.lowerBound <= messageContentFrame.maxY else { continue }
                                    let lower = max(interval.lowerBound, messageContentFrame.minY)
                                    let upper = min(interval.upperBound, messageContentFrame.maxY)
                                    if lower > coveredThrough + 1 {
                                        XCTFail(
                                            "\(caseID): recovery diagnostic has a vertical visibility gap before \(lower)"
                                        )
                                        break
                                    }
                                    coveredThrough = max(coveredThrough, upper)
                                }
                                XCTAssertGreaterThanOrEqual(
                                    coveredThrough,
                                    messageContentFrame.maxY - 1,
                                    "\(caseID): scroll sweep must cover the complete recovery diagnostic"
                                )
                            } else {
                                XCTFail("\(caseID): complete recovery diagnostic element was not rendered")
                            }
                            for action in failure.actions {
                                XCTAssertTrue(reached.contains(action.title),
                                              "\(caseID): recovery action \(action.title) must be reachable")
                            }
                        }
                    }
                }
            }
        }
    }

    private func assertFreshProgress(_ startup: AppStartupModel, fixture: Fixture,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let app = try XCTUnwrap(startup.appModel, file: file, line: line)
        let saved = try XCTUnwrap(fixture.store.loadProgress(), file: file, line: line)
        let restored = try DailyClassicGame(puzzle: app.daily.puzzle,
                                           acceptedWords: Set(packs().daily.acceptedGuesses), restoring: saved)
        XCTAssertEqual(saved, app.daily.game.progress, file: file, line: line)
        XCTAssertEqual(saved.puzzleID, app.daily.puzzle.id, file: file, line: line)
        XCTAssertTrue(restored.rows.isEmpty, file: file, line: line)
        XCTAssertTrue(restored.draft.isEmpty, file: file, line: line)
        XCTAssertNil(restored.completion, file: file, line: line)
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func packs() throws -> (tutorial: WordPack, daily: DailyWordPack) {
        (try WordPack.load(bundle: .main), try DailyWordPack.load(bundle: .main))
    }

    private func makeApp(_ daily: DailyWordPack, _ tutorial: WordPack, _ store: DailyClassicStore) throws -> DailyAccountCoordinator {
        try DailyAccountCoordinator(dailyPack: daily, tutorialPack: tutorial, guestStore: store, accountService: nil)
    }

    private struct Fixture {
        let root: URL
        let original: [String: Data]
        var store: DailyClassicStore { DailyClassicStore(directory: root) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "GridRaceStartupTests-\(UUID())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let guest = DailyClassicStore(directory: root)
            try guest.save(DailyClassicHistory())
            for userID in [UUID(), UUID()] {
                let account = AccountDailyClassicStore(rootDirectory: root, userID: userID)
                try account.save(DailyClassicHistory())
                try account.save(DailySyncMetadata())
            }
            try Data("unrelated root file".utf8).write(to: root.appending(path: "retained.txt"))
            original = try Self.snapshot(root)
        }

        func snapshot() throws -> [String: Data] { try Self.snapshot(root) }
        func remove() { try? FileManager.default.removeItem(at: root) }

        private static func snapshot(_ root: URL) throws -> [String: Data] {
            let urls = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
            var files: [String: Data] = [:]
            for case let url as URL in urls {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    files[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
                }
            }
            return files
        }
    }
}
