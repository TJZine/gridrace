import Foundation
import Supabase

struct DailyImportedResultsCursor: Equatable, Sendable {
    let puzzleDay: Int
    let puzzleID: String

    init(_ result: DailyImportedResultDTO) {
        puzzleDay = result.puzzleDay
        puzzleID = result.puzzleID
    }

    func precedes(_ other: Self) -> Bool {
        puzzleDay < other.puzzleDay || (puzzleDay == other.puzzleDay && puzzleID < other.puzzleID)
    }
}

actor SupabaseDailySyncRemote: DailySyncRemote {
    private let client: SupabaseClient
    private let pageSize: Int
    private let fetchProgress: @Sendable () async throws -> [DailyProgressDTO]
    private let fetchResultsPage: @Sendable (DailyImportedResultsCursor?, Int) async throws -> [DailyImportedResultDTO]

    init(client: SupabaseClient, pageSize: Int = 1000) {
        precondition(pageSize > 0, "Imported-results page size must be positive")
        self.client = client
        self.pageSize = pageSize
        fetchProgress = {
            let rows: [DailyProgressDTO] = try await client
                .from("daily_progress")
                .select()
                .order("puzzle_day", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows
        }
        fetchResultsPage = { cursor, limit in
            var request = client
                .from("daily_imported_results")
                .select()
            if let cursor {
                request = request.or(
                    "puzzle_day.gt.\(cursor.puzzleDay),and(puzzle_day.eq.\(cursor.puzzleDay),puzzle_id.gt.\(cursor.puzzleID))"
                )
            }
            let rows: [DailyImportedResultDTO] = try await request
                .order("puzzle_day", ascending: true)
                .order("puzzle_id", ascending: true)
                .limit(limit)
                .execute()
                .value
            return rows
        }
    }

    init(
        client: SupabaseClient,
        pageSize: Int = 1000,
        fetchProgress: @escaping @Sendable () async throws -> [DailyProgressDTO],
        fetchResultsPage: @escaping @Sendable (DailyImportedResultsCursor?, Int) async throws -> [DailyImportedResultDTO]
    ) {
        precondition(pageSize > 0, "Imported-results page size must be positive")
        self.client = client
        self.pageSize = pageSize
        self.fetchProgress = fetchProgress
        self.fetchResultsPage = fetchResultsPage
    }

    func pull() async throws -> DailyCloudSnapshot {
        do {
            async let progressRequest = fetchProgress()
            let importedResults = try await fetchAllImportedResults()
            let progress = try await progressRequest
            return DailyCloudSnapshot(progress: progress.first, importedResults: importedResults)
        } catch let error as DailySyncRemoteError {
            throw error
        } catch is DecodingError {
            throw DailySyncRemoteError.invalidData
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DailySyncRemoteError.unavailable
        }
    }

    private func fetchAllImportedResults() async throws -> [DailyImportedResultDTO] {
        var all: [DailyImportedResultDTO] = []
        var cursor: DailyImportedResultsCursor?
        while true {
            try Task.checkCancellation()
            let page = try await fetchResultsPage(cursor, pageSize)
            for result in page {
                let next = DailyImportedResultsCursor(result)
                guard cursor?.precedes(next) ?? true else {
                    throw DailySyncRemoteError.invalidData
                }
                cursor = next
            }
            all.append(contentsOf: page)
            if page.count < pageSize {
                break
            }
        }
        return all
    }

    func pushProgress(_ progress: DailyProgressUploadDTO) async throws -> DailyProgressPushOutcome {
        do {
            let response: ProgressResponse = try await client
                .rpc("sync_daily_progress", params: ProgressParameters(progress))
                .execute()
                .value

            if let error = response.error { throw error.remoteError }
            switch response.status {
            case "inserted", "exact", "advanced":
                return .stored(try response.requiredProgress())
            case "server_ahead":
                return .serverAhead(try response.requiredProgress())
            case "completed":
                return .completed(try response.requiredResult())
            case "conflict":
                if let saved = response.progress { return .conflict(.progress(saved)) }
                if let saved = response.result { return .conflict(.completed(saved)) }
                throw DailySyncRemoteError.invalidData
            default:
                throw DailySyncRemoteError.invalidData
            }
        } catch let error as DailySyncRemoteError {
            throw error
        } catch is DecodingError {
            throw DailySyncRemoteError.invalidData
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DailySyncRemoteError.unavailable
        }
    }

    func importResult(_ result: DailyImportedResultUploadDTO) async throws -> DailyResultImportOutcome {
        do {
            let response: ResultResponse = try await client
                .rpc("import_daily_result", params: ResultParameters(result))
                .execute()
                .value

            if let error = response.error { throw error.remoteError }
            switch response.status {
            case "inserted", "exact":
                return .stored(try response.requiredResult())
            case "conflict":
                if let saved = response.result { return .conflict(.result(saved)) }
                if let saved = response.progress { return .conflict(.progress(saved)) }
                throw DailySyncRemoteError.invalidData
            default:
                throw DailySyncRemoteError.invalidData
            }
        } catch let error as DailySyncRemoteError {
            throw error
        } catch is DecodingError {
            throw DailySyncRemoteError.invalidData
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DailySyncRemoteError.unavailable
        }
    }
}

struct ProgressParameters: Encodable, Sendable {
    let pPuzzleID: String
    let pPuzzleNumber: Int
    let pPuzzleDay: Int
    let pWordPackID: String
    let pScheduleVersion: Int
    let pHardModeEnabled: Bool
    let pGuesses: [DailyGuessDTO]
    let pExpectedRevision: Int?

    init(_ progress: DailyProgressUploadDTO) {
        pPuzzleID = progress.puzzleID
        pPuzzleNumber = progress.puzzleNumber
        pPuzzleDay = progress.puzzleDay
        pWordPackID = progress.wordPackID
        pScheduleVersion = progress.scheduleVersion
        pHardModeEnabled = progress.hardModeEnabled
        pGuesses = progress.guesses
        pExpectedRevision = progress.expectedRevision
    }

    private enum CodingKeys: String, CodingKey {
        case pPuzzleID = "p_puzzle_id"
        case pPuzzleNumber = "p_puzzle_number"
        case pPuzzleDay = "p_puzzle_day"
        case pWordPackID = "p_word_pack_id"
        case pScheduleVersion = "p_schedule_version"
        case pHardModeEnabled = "p_hard_mode_enabled"
        case pGuesses = "p_guesses"
        case pExpectedRevision = "p_expected_revision"
    }
}

private struct ResultParameters: Encodable, Sendable {
    let pPuzzleID: String
    let pPuzzleNumber: Int
    let pPuzzleDay: Int
    let pWordPackID: String
    let pScheduleVersion: Int
    let pHardModeEnabled: Bool
    let pGuesses: [DailyGuessDTO]
    let pOutcome: DailyOutcome
    let pGuessCount: Int
    let pClientCompletedAt: String

    init(_ result: DailyImportedResultUploadDTO) {
        pPuzzleID = result.puzzleID
        pPuzzleNumber = result.puzzleNumber
        pPuzzleDay = result.puzzleDay
        pWordPackID = result.wordPackID
        pScheduleVersion = result.scheduleVersion
        pHardModeEnabled = result.hardModeEnabled
        pGuesses = result.guesses
        pOutcome = result.outcome
        pGuessCount = result.guessCount
        pClientCompletedAt = result.clientCompletedAt.dailyWireTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case pPuzzleID = "p_puzzle_id"
        case pPuzzleNumber = "p_puzzle_number"
        case pPuzzleDay = "p_puzzle_day"
        case pWordPackID = "p_word_pack_id"
        case pScheduleVersion = "p_schedule_version"
        case pHardModeEnabled = "p_hard_mode_enabled"
        case pGuesses = "p_guesses"
        case pOutcome = "p_outcome"
        case pGuessCount = "p_guess_count"
        case pClientCompletedAt = "p_client_completed_at"
    }
}

private struct SyncErrorPayload: Decodable, Sendable {
    let code: String

    var remoteError: DailySyncRemoteError {
        code == "invalid_daily_payload" ? .invalidData : .rejected
    }
}

private struct ProgressResponse: Decodable, Sendable {
    let status: String?
    let progress: DailyProgressDTO?
    let result: DailyImportedResultDTO?
    let error: SyncErrorPayload?

    func requiredProgress() throws -> DailyProgressDTO {
        guard let progress else { throw DailySyncRemoteError.invalidData }
        return progress
    }

    func requiredResult() throws -> DailyImportedResultDTO {
        guard let result else { throw DailySyncRemoteError.invalidData }
        return result
    }
}

private typealias ResultResponse = ProgressResponse
