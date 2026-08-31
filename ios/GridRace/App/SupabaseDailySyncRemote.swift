import Foundation
import Supabase

actor SupabaseDailySyncRemote: DailySyncRemote {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func pull() async throws -> DailyCloudSnapshot {
        do {
            async let progressRequest: [DailyProgressDTO] = client
                .from("daily_progress")
                .select()
                .order("puzzle_day", ascending: false)
                .limit(1)
                .execute()
                .value
            async let resultRequest: [DailyImportedResultDTO] = client
                .from("daily_imported_results")
                .select()
                .order("puzzle_day", ascending: true)
                .execute()
                .value
            let (progress, results) = try await (progressRequest, resultRequest)
            return DailyCloudSnapshot(progress: progress.first, importedResults: results)
        } catch is DecodingError {
            throw DailySyncRemoteError.invalidData
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DailySyncRemoteError.unavailable
        }
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
