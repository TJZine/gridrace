import Foundation

struct PendingLiveInvitation: Codable, Equatable, Hashable, Sendable {
    static let currentFormat = 1
    static let unassignedGeneration = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    let format: Int
    let origin: String
    let code: String
    let replacementGeneration: UUID

    init(
        format: Int = PendingLiveInvitation.currentFormat,
        origin: String,
        code: String,
        replacementGeneration: UUID = PendingLiveInvitation.unassignedGeneration
    ) {
        self.format = format
        self.origin = origin
        self.code = code
        self.replacementGeneration = replacementGeneration
    }

    var isPersistable: Bool {
        format == Self.currentFormat
            && LiveInvitationParser.normalizedOrigin(origin) == origin
            && LiveInvitationParser.canonicalCode(code) == code
    }
}

enum LiveInvitationParserError: Error, Equatable, Sendable {
    case invalidConfiguredOrigin
}

struct LiveInvitationParser: Sendable {
    private let allowedOrigins: Set<String>

    init(allowedOrigins: [URL]) throws {
        let normalized = try Set(allowedOrigins.map { origin in
            guard let normalized = Self.normalizedOrigin(url: origin) else {
                throw LiveInvitationParserError.invalidConfiguredOrigin
            }
            return normalized
        })
        guard !normalized.isEmpty else {
            throw LiveInvitationParserError.invalidConfiguredOrigin
        }
        self.allowedOrigins = normalized
    }

    func parse(_ url: URL) -> PendingLiveInvitation? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              !host.isEmpty,
              components.percentEncodedPath == components.path,
              components.percentEncodedPath.hasPrefix("/join/")
        else { return nil }

        let origin = "https://\(host.lowercased())"
        guard allowedOrigins.contains(origin) else { return nil }

        let encodedPath = components.percentEncodedPath
        let rawCode = String(encodedPath.dropFirst("/join/".count))
        guard !rawCode.contains("/"), let code = Self.canonicalCode(rawCode) else {
            return nil
        }
        return PendingLiveInvitation(origin: origin, code: code)
    }

    static func canonicalCode(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        guard bytes.count == 6 else { return nil }

        var canonical = [UInt8]()
        canonical.reserveCapacity(bytes.count)
        for byte in bytes {
            let uppercased: UInt8
            switch byte {
            case 97...122:
                uppercased = byte - 32
            default:
                uppercased = byte
            }
            guard isAllowedCodeByte(uppercased) else { return nil }
            canonical.append(uppercased)
        }
        return String(decoding: canonical, as: UTF8.self)
    }

    static func normalizedOrigin(_ value: String) -> String? {
        guard let url = URL(string: value) else { return nil }
        return normalizedOrigin(url: url)
    }

    private static func normalizedOrigin(url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              !host.isEmpty,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { return nil }
        return "https://\(host.lowercased())"
    }

    private static func isAllowedCodeByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 65...72, 74...78, 80...90, 50...57:
            return true
        default:
            return false
        }
    }
}

enum PendingLiveInvitationStoreError: Error, Equatable, Sendable {
    case invalidData
    case unavailable
}

enum PendingLiveInvitationStoreSaveResult: Equatable, Sendable {
    case saved(PendingLiveInvitation)
    case duplicate(PendingLiveInvitation)
    case replaced(PendingLiveInvitation)
}

protocol PendingLiveInvitationPersistence: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

struct ProtectedPendingLiveInvitationFile: PendingLiveInvitationPersistence, Sendable {
    let directory: URL
    private let filename: String

    init(directory: URL, filename: String = "pending-live-invitation-v1.json") {
        self.directory = directory
        self.filename = filename
    }

    private var fileURL: URL { directory.appending(path: filename) }

    func read() throws -> Data? {
        try PersistenceFile.readIfPresent(at: fileURL)
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func remove() throws {
        try PersistenceFile.removeIfPresent(at: fileURL)
    }
}

final class PendingLiveInvitationStore: @unchecked Sendable {
    private static let processLock = NSLock()
    private let persistence: any PendingLiveInvitationPersistence

    init(persistence: any PendingLiveInvitationPersistence) {
        self.persistence = persistence
    }

    init(directory: URL) {
        persistence = ProtectedPendingLiveInvitationFile(directory: directory)
    }

    static func applicationSupport() throws -> PendingLiveInvitationStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return PendingLiveInvitationStore(
            directory: base.appending(path: "GridRace", directoryHint: .isDirectory)
        )
    }

    func load() throws -> PendingLiveInvitation? {
        try withProcessLock { try loadUnlocked() }
    }

    @discardableResult
    func save(_ invitation: PendingLiveInvitation) throws -> PendingLiveInvitationStoreSaveResult {
        try withProcessLock {
            guard invitation.format == PendingLiveInvitation.currentFormat,
                  LiveInvitationParser.normalizedOrigin(invitation.origin) == invitation.origin,
                  LiveInvitationParser.canonicalCode(invitation.code) == invitation.code
            else { throw PendingLiveInvitationStoreError.invalidData }

            let existing = try loadUnlocked()
            if let existing, existing.code == invitation.code {
                return .duplicate(existing)
            }

            let stored = PendingLiveInvitation(
                origin: invitation.origin,
                code: invitation.code,
                replacementGeneration: UUID()
            )
            do {
                try persistence.write(try JSONEncoder().encode(stored))
            } catch {
                throw PendingLiveInvitationStoreError.unavailable
            }
            return existing == nil ? .saved(stored) : .replaced(stored)
        }
    }

    func clear() throws {
        try withProcessLock {
            do { try persistence.remove() }
            catch { throw PendingLiveInvitationStoreError.unavailable }
        }
    }

    @discardableResult
    func clear(matchingGeneration generation: UUID) throws -> Bool {
        try withProcessLock {
            guard let existing = try loadUnlocked(),
                  existing.replacementGeneration == generation
            else { return false }
            do { try persistence.remove() }
            catch { throw PendingLiveInvitationStoreError.unavailable }
            return true
        }
    }

    private func loadUnlocked() throws -> PendingLiveInvitation? {
        let data: Data?
        do { data = try persistence.read() }
        catch { throw PendingLiveInvitationStoreError.unavailable }
        guard let data else { return nil }

        do {
            let invitation = try JSONDecoder().decode(PendingLiveInvitation.self, from: data)
            guard invitation.replacementGeneration != PendingLiveInvitation.unassignedGeneration,
                  invitation.isPersistable else {
                throw PendingLiveInvitationStoreError.invalidData
            }
            return invitation
        } catch let error as PendingLiveInvitationStoreError {
            throw error
        } catch {
            throw PendingLiveInvitationStoreError.invalidData
        }
    }

    private func withProcessLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return try operation()
    }
}
