// Disposable test-only key; never used by the production app or release scripts.
import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
FileManager.default.createFile(atPath: destination.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600])
print(key.publicKey.rawRepresentation.base64EncodedString())
