//
//  HTTPPairingServerTests.swift
//  RemoteLinkKitTests
//
//  Created by Haoran on 2026/10/25.
//

import XCTest
@testable import RemoteLinkKit

#if canImport(Network)

final class HTTPPairingServerTests: XCTestCase {

    private let server = HTTPPairingServer { _ in
        HTTPPairingServer.Response(status: 200)
    }

    // MARK: - Helpers

    /// 构造一个原始 HTTP 请求字节流
    private func makeRequest(
        method: String = "POST",
        path: String = "/pair/verify",
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> Data {
        var lines = ["\(method) \(path) HTTP/1.1"]
        var headers = headers
        // 默认补 Content-Length，除非调用方显式给了（包括想构造非法值的情况）
        if headers["Content-Length"] == nil,
           !headers.keys.contains(where: { $0.lowercased() == "content-length" }) {
            headers["Content-Length"] = "\(body.count)"
        }
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            lines.append("\(k): \(v)")
        }
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        data.append(body)
        return data
    }

    // MARK: - Happy path

    func testParseSimpleRequest() {
        let body = Data(#"{"proof":"abc"}"#.utf8)
        let raw = makeRequest(
            method: "POST",
            path: "/pair/verify",
            headers: ["Content-Type": "application/json"],
            body: body
        )

        switch server.tryParseRequest(raw) {
        case .request(let parsed):
            XCTAssertEqual(parsed.request.method, "POST")
            XCTAssertEqual(parsed.request.path, "/pair/verify")
            XCTAssertEqual(parsed.request.body, body)
            XCTAssertEqual(parsed.request.headers["content-type"], "application/json")
            XCTAssertEqual(parsed.consumed, raw.count)
        default:
            XCTFail("should parse a complete request")
        }
    }

    func testMethodIsUppercased() {
        let raw = makeRequest(method: "get", path: "/pair/hello")
        switch server.tryParseRequest(raw) {
        case .request(let parsed):
            XCTAssertEqual(parsed.request.method, "GET")
        default:
            XCTFail("should parse")
        }
    }

    func testHeaderKeysAreLowercased() {
        let raw = makeRequest(headers: ["X-Custom-Header": "Value"])
        switch server.tryParseRequest(raw) {
        case .request(let parsed):
            XCTAssertEqual(parsed.request.headers["x-custom-header"], "Value")
        default:
            XCTFail("should parse")
        }
    }

    func testEmptyBodyWithZeroContentLength() {
        let raw = makeRequest(method: "GET", path: "/pair/hello", body: Data())
        switch server.tryParseRequest(raw) {
        case .request(let parsed):
            XCTAssertTrue(parsed.request.body.isEmpty)
        default:
            XCTFail("should parse")
        }
    }

    // MARK: - Incomplete

    func testIncompleteHeaders() {
        let raw = Data("POST /pair/verify HTTP/1.1\r\nContent-Length: 5\r\n".utf8)
        if case .incomplete = server.tryParseRequest(raw) {} else {
            XCTFail("should be incomplete")
        }
    }

    func testIncompleteBody() {
        // 声明 10 字节，只给 3 字节
        let raw = Data("POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)
        if case .incomplete = server.tryParseRequest(raw) {} else {
            XCTFail("should be incomplete")
        }
    }

    func testEmptyBufferIsIncomplete() {
        if case .incomplete = server.tryParseRequest(Data()) {} else {
            XCTFail("should be incomplete")
        }
    }

    // MARK: - Reject 400: malformed request line

    func testMalformedRequestLine() {
        // 没有 path
        let raw = Data("BADREQUEST\r\nContent-Length: 0\r\n\r\n".utf8)
        if case .reject(let status) = server.tryParseRequest(raw) {
            XCTAssertEqual(status, 400)
        } else {
            XCTFail("should reject with 400")
        }
    }

    // MARK: - Reject 400: bad Content-Length

    func testNegativeContentLengthRejected() {
        // 负数若不拒绝，bodyStart..<bodyEnd 构成非法 Range 会崩溃
        let raw = Data("POST /x HTTP/1.1\r\nContent-Length: -5\r\n\r\n".utf8)
        if case .reject(let status) = server.tryParseRequest(raw) {
            XCTAssertEqual(status, 400)
        } else {
            XCTFail("should reject negative Content-Length with 400")
        }
    }

    func testUnparsableContentLengthRejected() {
        let raw = Data("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n".utf8)
        if case .reject(let status) = server.tryParseRequest(raw) {
            XCTAssertEqual(status, 400)
        } else {
            XCTFail("should reject unparsable Content-Length with 400")
        }
    }

    // MARK: - Reject 413: body too large

    func testBodyTooLargeRejected() {
        let tooBig = HTTPPairingServer.maxBodySize + 1
        let raw = Data("POST /x HTTP/1.1\r\nContent-Length: \(tooBig)\r\n\r\n".utf8)
        if case .reject(let status) = server.tryParseRequest(raw) {
            XCTAssertEqual(status, 413)
        } else {
            XCTFail("should reject oversized body with 413")
        }
    }

    func testBodyExactlyAtLimitIsNotRejected() {
        // 声明 = maxBodySize，body 还没到，应该是 incomplete 而不是 413
        let raw = Data("POST /x HTTP/1.1\r\nContent-Length: \(HTTPPairingServer.maxBodySize)\r\n\r\n".utf8)
        if case .incomplete = server.tryParseRequest(raw) {} else {
            XCTFail("exactly at limit should be incomplete, not rejected")
        }
    }

    // MARK: - Response defaults

    func testResponseDefaultHeaders() {
        let resp = HTTPPairingServer.Response(status: 200)
        XCTAssertEqual(resp.headers["Content-Type"], "application/json")
        XCTAssertTrue(resp.body.isEmpty)
    }
}

#endif
