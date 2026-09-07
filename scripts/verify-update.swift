import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

guard CommandLine.arguments.count == 4 else { fail("Usage: verify-update.swift archive Info.plist signature") }
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
guard let encodedKey = info?["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: encodedKey),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else { fail("Invalid update verification metadata.") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
guard key.isValidSignature(signature, for: archive) else { fail("Update signature does not match the shipped public key.") }
print("Update signature verified against the shipped public key.")
