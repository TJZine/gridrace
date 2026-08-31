import CryptoKit
import Foundation
import Security

enum AppleNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func generate(length: Int = 32) throws -> String {
        precondition(length > 0)
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
                throw AppleNonceError.randomGenerationFailed
            }
            guard byte < UInt8.max - (UInt8.max % UInt8(alphabet.count)) else { continue }
            result.append(alphabet[Int(byte) % alphabet.count])
        }
        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum AppleNonceError: Error {
    case randomGenerationFailed
}
