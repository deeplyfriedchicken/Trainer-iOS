import CryptoKit
import Foundation

// Mirrors server-side encryptUserId in src/lib/client-token.ts.
// Format: base64url( iv[12] + authTag[16] + ciphertext ) using AES-256-GCM.
func encryptClientToken(userId: String) -> String? {
    let hex = Config.clientTokenSecret
    guard hex.count == 64, let keyData = Data(hexString: hex) else { return nil }

    let key = SymmetricKey(data: keyData)
    let ttlMs: Int64 = 30 * 24 * 60 * 60 * 1000
    let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + ttlMs
    let payload = "\(userId):\(expiresAt)"

    guard let payloadData = payload.data(using: .utf8) else { return nil }

    do {
        let sealed = try AES.GCM.seal(payloadData, using: key)
        guard let combined = sealed.combined else { return nil }
        // combined is nonce(12) + ciphertext + tag(16) from CryptoKit —
        // reorder to match server layout: iv(12) + tag(16) + ciphertext
        let nonce = combined.prefix(12)
        let ciphertext = combined.dropFirst(12).dropLast(16)
        let tag = combined.suffix(16)
        var reordered = Data()
        reordered.append(contentsOf: nonce)
        reordered.append(contentsOf: tag)
        reordered.append(contentsOf: ciphertext)
        return reordered.base64URLEncoded()
    } catch {
        return nil
    }
}

func clientPortalURL(for userId: String) -> String? {
    guard let token = encryptClientToken(userId: userId) else { return nil }
    return "\(Config.clientPortalBaseURL)/client/\(token)"
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
