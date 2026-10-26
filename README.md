# RemoteLinkKit

> WebSocket transport and encrypted framing protocol for remote shell clients and servers on macOS and iOS.

---

## Overview

RemoteLinkKit is a Swift package that provides the plumbing for remote command execution over WebSocket. It is split into two libraries:

| Library | Responsibility |
|---------|----------------|
| `RemoteLinkKit` | Connection and transport: WebSocket, HTTP pairing, Bonjour discovery, heartbeat, reconnect |
| `RemoteProcessProtocol` | Framing and security: frame codec, cipher suites, key derivation, pairing, message codec, replay protection |

Both libraries are **UI-free**, **execution-free**, and **Network-framework-thin**. They do not render ANSI output, spawn processes, or store tokens. Those are left to the host application.

---

## Requirements

- macOS 12.4 or later
- iOS 15 or later
- Swift 5.9 or later
- Xcode 15 or later (Tested with Xcode 26.3)

---

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/CaoHaoran-Dev/RemoteLinkKit.git", from: "0.1.0")
]
```

Add the product you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RemoteLinkKit", package: "RemoteLinkKit"),
        .product(name: "RemoteProcessProtocol", package: "RemoteLinkKit")
    ]
)
```

`RemoteProcessProtocol` depends on `RemoteLinkKit`, so adding only the protocol product pulls in the transport product automatically.

---

## RemoteLinkKit

### RemoteConnection

A `RemoteConnection` is the byte-level abstraction over a WebSocket link. It only sends and receives `Data`, and reports state changes.

```swift
public protocol RemoteConnection: AnyObject, Sendable {
    var state: ConnectionState { get }
    var onStateChange: (@Sendable (ConnectionState) -> Void)? { get set }
    var onReceive: (@Sendable (Data) -> Void)? { get set }

    func connect() async throws
    func send(_ data: Data) async throws
    func close()
}
```

Two implementations are provided:

| Type | Side | Backing API |
|------|------|-------------|
| `URLSessionTransport` | Client | `URLSessionWebSocketTask` |
| `NWTransport` | Server | `NWConnection` + `NWProtocolWebSocket` |

### ConnectionConfig

```swift
let config = ConnectionConfig(
    host: "192.168.1.10",
    port: 52731,          // WebSocket port
    pairingPort: 52732,   // HTTP pairing port (optional)
    scheme: .ws,
    connectTimeout: 10
)
```

### Client example

```swift
import RemoteLinkKit

let config = ConnectionConfig(host: "127.0.0.1", port: 52731)
let transport = URLSessionTransport(
    config: config,
    transform: PassthroughTransform(),
    reconnectPolicy: ReconnectPolicy()
)

transport.onReceive = { data in
    // raw bytes from the server
}

try await transport.connect()
try await transport.send(Data("hello".utf8))
```

### ConnectionTransform

`ConnectionTransform` is the injection point for encryption and framing. `RemoteLinkKit` calls `encode` before sending and `decode` after receiving.

```swift
public protocol ConnectionTransform: Sendable {
    func encode(_ data: Data) throws -> Data
    func decode(_ data: Data) throws -> Data
}
```

Pass `PassthroughTransform()` to use the transport with plain bytes, or inject a transform from `RemoteProcessProtocol` for encrypted framing.

### HTTP pairing

`HTTPPairingClient` sends pairing requests. It returns raw `Data`; parsing is up to the caller.

```swift
let client = HTTPPairingClient(config: config)
let helloResponse = try await client.hello()
let verifyResponse = try await client.verify(body: proofData)
```

`HTTPPairingServer` parses minimal HTTP/1.1 requests and hands them to a handler. It only supports `Content-Length` bodies, not chunked encoding.

```swift
let server = HTTPPairingServer { request in
    HTTPPairingServer.Response(status: 200, body: jsonData)
}
try server.start(port: 52732)
```

### Bonjour

```swift
let browser = BonjourBrowser(serviceType: "_runprocess._tcp")
browser.onFound = { service in
    // service.name, service.endpoint
}
browser.start()

let advertiser = BonjourAdvertiser(serviceName: "My Mac", port: 52732)
advertiser.start()
```

### Heartbeat

```swift
let heartbeat = HeartbeatController(interval: 30, timeout: 10)
heartbeat.onSendPing = { /* send a ping frame */ }
heartbeat.onTimeout = { /* close the connection */ }
heartbeat.start()

// call when a pong arrives
heartbeat.receivedPong()
```

A timeout fires only when a ping is outstanding and no pong has arrived within `timeout` seconds. Pings do not reset the timeout timer. The timeout check is based on the **exact time the ping was sent**, preventing false positives when `interval > timeout`.

> **Note for Unit Testing**: `DispatchSourceTimer` behavior can be unpredictable in XCTest environments (often silently failing to fire). The controller automatically detects the XCTest environment and uses a deterministic fallback (simulated async scheduling) to ensure tests pass reliably. Production builds are unaffected.

### Reconnect

`ReconnectPolicy` computes exponential backoff. It does not reconnect by itself; pass it to `URLSessionTransport` or use it in your own loop.

```swift
let policy = ReconnectPolicy(initialDelay: 1, multiplier: 2, maxDelay: 30, maxAttempts: 10)
policy.delay(forAttempt: 0) // 1.0
policy.delay(forAttempt: 5) // 30.0
policy.delay(forAttempt: 10) // nil
```

---

## RemoteProcessProtocol

### Frame

Every message travels in a frame:

```
[version:1][type:1][cipherId:2][seq:4][length:4][payload:length]
```

- `payload` is the encrypted JSON message.
- `seq` is monotonic per sender and used for nonce derivation and replay protection.
- `cipherId` selects the cipher suite. New suites can be added without changing the frame layout.
- `version` is reserved for future protocol evolution.

### Cipher suites

| Suite | Identifier | `cipherId` | Key length |
|-------|-----------|------------|------------|
| AES-256-GCM | `AES-256-GCM` | `0x0001` | 32 bytes |
| ChaCha20-Poly1305 | `ChaCha20-Poly1305` | `0x0002` | 32 bytes |

Both are backed by CryptoKit and produce a 16-byte authentication tag.

```swift
let cipher = try AESGCMCipher(key: sessionKey)
let sealed = try cipher.seal(plaintext, nonce: nonce, aad: aad)
let opened = try cipher.open(sealed, nonce: nonce, aad: aad)
```

### Key derivation

```swift
let sessionKey = KeyDerivation.deriveKey(
    sharedSecret: sharedSecret,
    salt: clientNonce + serverNonce,
    info: Data("session".utf8)
)

let nonce = KeyDerivation.nonce(from: seq)
```

The nonce is derived from the frame sequence number. Each connection must use a fresh session key.

### Pairing

The 6-digit pairing code is never sent over the wire. It is used as HKDF input and as an HMAC proof.

```swift
// Server side
let code = PairingCode()          // 6 digits, 10-minute validity
let codeString = code.code        // show this to the user

// Client side
let hello = /* parse HelloResponse */
let pairKey = PairingHandshake.derivePairKey(
    code: userInput,
    serverId: hello.serverId,
    nonce: Data(hexString: hello.nonce)
)
let proof = PairingHandshake.computeProof(pairKey: pairKey, nonce: nonce)

// Server side
try code.verify(userInput)        // lockout after 5 failures, invalid after 10
```

After a successful pairing, the server issues a `PairingToken`. The server stores only the SHA-256 hash; the client stores the raw token in the Keychain.

```swift
let token = PairingToken.generate(deviceName: "iPhone")
let hash = token.hash()           // store on server

// later
let ok = PairingToken.verify(rawValue: clientToken, againstHash: storedHash)
```

### Messages

Client to server:

| Message | Frame type | Payload |
|---------|-----------|---------|
| `.exec(id, cmd, timeout)` | `.exec` | command, timeout |
| `.cancel(id)` | `.cancel` | command id |
| `.ping(timestamp)` | `.ping` | timestamp |

Server to client:

| Message | Frame type | Payload |
|---------|-----------|---------|
| `.output(id, stream, data)` | `.output` | stdout / stderr chunk |
| `.done(id, exit, cwd)` | `.done` | exit code, working directory |
| `.error(id, message)` | `.error` | error text |
| `.pong(timestamp)` | `.pong` | timestamp |
| `.cwd(path)` | `.cwd` | working directory |

```swift
let data = try MessageCodec.encode(ClientMessage.exec(id: "1", cmd: "ls", timeout: 10))
let msg = try MessageCodec.decodeClient(data)
```

### Replay protection

`ReplayGuard` maintains a sliding window of seen sequence numbers. Frames with a duplicate or out-of-window sequence number are rejected.

```swift
let guard = ReplayGuard(windowSize: 1024)
if guard.accept(frame.seq) {
    // process
} else {
    // drop
}
```

### SecureChannel

`SecureChannel` is an `actor` that wires a `RemoteConnection` together with framing, encryption, and message encoding. It is the recommended entry point for application code.

```swift
import RemoteLinkKit
import RemoteProcessProtocol

let cipher = try AESGCMCipher(key: sessionKey)
let channel = SecureChannel(
    transport: transport,
    cipher: cipher,
    cipherId: AESGCMCipher.cipherId,
    isClient: true
)

await channel.setOnServerMessage { msg in
    switch msg {
    case .output(_, _, let data):
        print(String(data: data, encoding: .utf8) ?? "")
    case .done(_, let exit, let cwd):
        print("exit \(exit) in \(cwd)")
    default:
        break
    }
}

await channel.setOnError { error in
    print("channel error:", error)
}

await channel.start()
try await channel.send(.exec(id: "1", cmd: "ls -la", timeout: 10))
```

---

## Architecture

```
┌───────────────────────────────────────────────┐
│ Host application                              │
│  pairing UI · host list · exec/output · ANSI  │
├───────────────────────────────────────────────┤
│ RemoteProcessProtocol                         │
│  frame · cipher · pairing · messages · replay │
├───────────────────────────────────────────────┤
│ RemoteLinkKit                                 │
│  websocket · http · bonjour · heartbeat ·     │
│  reconnect · ConnectionTransform              │
├───────────────────────────────────────────────┤
│ Network.framework / URLSession                │
└───────────────────────────────────────────────┘
```

`RemoteProcessProtocol` plugs into `RemoteLinkKit` through `ConnectionTransform`. The transport layer does not know about encryption or message semantics.

---

## Security notes

- The 6-digit pairing code is never transmitted. It is used to derive a pairing key and to produce an HMAC proof.
- Pairing attempts are rate-limited: 5 failures lock the code for 1 minute, 10 failures invalidate it.
- Session keys are derived per connection using HKDF over client and server nonces. They are never reused across connections.
- Each frame uses a nonce derived from its sequence number, and its header is authenticated as additional data.
- `ws://` does not authenticate the server at the transport layer. Use `wss://` or a VPN if you need transport-level identity.
- Application-layer encryption protects message contents and integrity. It does not protect against a compromised server host.
- The server stores token hashes only. The client stores the raw token in the Keychain.

---

## What this package does not do

- Render ANSI colors or manage text views.
- Spawn or manage shell processes.
- Store pairing tokens or host configuration.
- Provide a UI for pairing or connection management.
- Implement interactive TUI passthrough.

Those belong to the host application.

---

## License

MIT © 2026 CaoHaoran-Dev
