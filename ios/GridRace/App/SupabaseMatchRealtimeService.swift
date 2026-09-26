import Foundation
import Supabase

enum LiveMatchRealtimeEvent: Equatable, Sendable {
    case ready
    case signal
    case disconnected
}

protocol LiveMatchRealtimeServicing: Sendable {
    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error>
}

struct SupabaseMatchRealtimeService: LiveMatchRealtimeServicing, Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let channel = client.channel("live-match-\(matchID.uuidString)-\(UUID().uuidString)")
            let updates = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "matches",
                filter: .eq("id", value: matchID)
            )
            let statuses = channel.statusChange
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            var wasReady = false
                            for await status in statuses {
                                try Task.checkCancellation()
                                switch status {
                                case .subscribed:
                                    wasReady = true
                                    continuation.yield(.ready)
                                case .unsubscribed where wasReady:
                                    continuation.yield(.disconnected)
                                case .unsubscribed, .subscribing, .unsubscribing:
                                    break
                                }
                            }
                        }
                        group.addTask {
                            for await _ in updates {
                                try Task.checkCancellation()
                                continuation.yield(.signal)
                            }
                        }
                        try await group.waitForAll()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }
}
