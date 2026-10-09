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
    private let lease: AuthClientLease
    init(lease: AuthClientLease) { self.lease = lease }

    func events(matchID: UUID) -> AsyncThrowingStream<LiveMatchRealtimeEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let lifetime = lease.lifetime
                let registration = try lifetime.registerChannel(
                    topic: "live-match-\(matchID.uuidString)-\(UUID().uuidString)",
                    generation: lease.generation, finish: { continuation.finish() })
                let channel = registration.channel
                let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "matches",
                                                      filter: .eq("id", value: matchID))
                let statuses = channel.statusChange
                let task = Task {
                    do {
                        try lease.check()
                        try await channel.subscribeWithError()
                        try lease.check()
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                var wasReady = false
                                for await status in statuses {
                                    try Task.checkCancellation()
                                    try lease.check()
                                    switch status {
                                    case .subscribed: wasReady = true; continuation.yield(.ready)
                                    case .unsubscribed where wasReady: continuation.yield(.disconnected)
                                    case .unsubscribed, .subscribing, .unsubscribing: break
                                    }
                                }
                            }
                            group.addTask {
                                for await _ in updates {
                                    try Task.checkCancellation()
                                    try lease.check()
                                    continuation.yield(.signal)
                                }
                            }
                            try await group.waitForAll()
                        }
                        continuation.finish()
                    } catch is CancellationError { continuation.finish() }
                    catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                    Task { await lifetime.removeChannel(registration) }
                }
            } catch { continuation.finish(throwing: error) }
        }
    }
}
