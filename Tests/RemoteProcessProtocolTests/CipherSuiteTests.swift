//
//  CipherSuiteTests.swift
//  RemoteProcessProtocolTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteProcessProtocol

final class CipherSuiteTests: XCTestCase {

    private let key = Data(repeating: 0xAB, count: 32)
    private let nonce = Data(repeating: 0x01, count: 12)
    private let aad = Data("header".utf8)

    func testAESGCMRoundTrip() throws {
        let cipher = try AESGCMCipher(key: key)
        let plaintext = Data("secret message".utf8)
        let sealed = try cipher.seal(plaintext, nonce: nonce, aad: aad)
        let opened = try cipher.open(sealed, nonce: nonce, aad: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testChaChaRoundTrip() throws {
        let cipher = try ChaChaPolyCipher(key: key)
        let plaintext = Data("secret message".utf8)
        let sealed = try cipher.seal(plaintext, nonce: nonce, aad: aad)
        let opened = try cipher.open(sealed, nonce: nonce, aad: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testWrongAADFails() throws {
        let cipher = try AESGCMCipher(key: key)
        let sealed = try cipher.seal(Data("x".utf8), nonce: nonce, aad: aad)
        XCTAssertThrowsError(try cipher.open(sealed, nonce: nonce, aad: Data("other".utf8)))
    }

    func testInvalidKeyLength() {
        XCTAssertThrowsError(try AESGCMCipher(key: Data([1, 2, 3])))
    }

    func testRegistry() {
        XCTAssertEqual(CipherRegistry.identifier(for: AESGCMCipher.cipherId), AESGCMCipher.identifier)
        XCTAssertEqual(CipherRegistry.identifier(for: ChaChaPolyCipher.cipherId), ChaChaPolyCipher.identifier)
        XCTAssertNil(CipherRegistry.identifier(for: 0xFFFF))
    }

    func testKeyDerivationDeterministic() {
        let shared = Data("shared".utf8)
        let salt = Data("salt".utf8)
        let info = Data("info".utf8)
        let k1 = KeyDerivation.deriveKey(sharedSecret: shared, salt: salt, info: info)
        let k2 = KeyDerivation.deriveKey(sharedSecret: shared, salt: salt, info: info)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
    }
}
