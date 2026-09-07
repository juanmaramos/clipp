import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("Usage: check-update-key.swift Info.plist") }
guard let encoded = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
      let secret = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else {
  fail("SPARKLE_PRIVATE_KEY is missing or invalid base64.")
}
let publicKey: Data
switch secret.count {
case 32:
  publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation
case 96:
  // Sparkle's legacy format is a 64-byte expanded private key followed by its public key.
  publicKey = secret.suffix(32)
default:
  fail("SPARKLE_PRIVATE_KEY must use Sparkle's 32-byte seed or 96-byte legacy format.")
}
let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
let configured = publicKey.base64EncodedString()
print("Configured signing public key: \(configured)")
guard info?["SUPublicEDKey"] as? String == configured else {
  fail("The app's SUPublicEDKey does not match the configured signing key.")
}
print("Sparkle signing key matches the app.")
