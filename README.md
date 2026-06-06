# Livt.Net

`Livt.Net` provides fixed-size networking components for Livt hardware designs.
It focuses on small request/response stacks that can parse Ethernet frames,
classify common IPv4 traffic, and emit deterministic response bytes.

The 0.24.1 package surface is intentionally narrow and hardware-oriented:

- `Livt.Net.EthernetFrameParser`: fixed Ethernet II header parser.
- `Livt.Net.EthernetFrameBuilder`: Ethernet reply-header byte builder.
- `Livt.Net.ArpPacketParser`: ARP packet parser for Ethernet/IPv4 frames.
- `Livt.Net.ArpResponder`: ARP reply selector and byte builder.
- `Livt.Net.Ipv4PacketParser`: fixed 20-byte IPv4 header classifier.
- `Livt.Net.Ipv4HeaderBuilder`: IPv4 response-header byte builder.
- `Livt.Net.Ipv4HeaderChecksum`: checksum helper for fixed IPv4 responses.
- `Livt.Net.IcmpEchoResponder`: ICMP echo reply selector and byte builder.
- `Livt.Net.TcpHeaderParser`: fixed 20-byte TCP header classifier.
- `Livt.Net.TcpConnectionRecognizer`: TCP packet recognizer for local endpoints.
- `Livt.Net.TcpSegmentBuilder`: TCP response-header byte builder.
- `Livt.Net.TcpSynAckFrameComposer`: Ethernet/IPv4/TCP SYN-ACK frame composer.
- `Livt.Net.TcpChecksum`: checksum helper for fixed TCP responses.
- `Livt.Net.HttpGetRecognizer`: route-aware HTTP GET recognizer.
- `Livt.Net.HttpRequestRecognizer`: Ethernet/IPv4/TCP/HTTP GET recognizer.
- `Livt.Net.HttpResponseGenerator`: HTTP/1.0 response byte generator.
- `Livt.Net.HttpResponseFrameComposer`: Ethernet/IPv4/TCP/HTTP response composer.
- `Livt.Net.HttpServer`: stateful HTTP response selector over loaded frames.
- `Livt.Net.NetworkEndpoint`: ARP, ICMP, TCP, and HTTP endpoint dispatcher.
- `Livt.Net.WebServer`: compact wrapper around `NetworkEndpoint`.
- `Livt.Net.EthernetFrameIo`: frame buffer and AXI4-Lite EthernetLite boundary.
- `Livt.Net.Axi4LiteEthernetLiteAdapter`: AXI4-Lite EthernetLite signal adapter.
- `Livt.Net.IAxi4LiteEthernetLiteMaster`: AXI4-Lite EthernetLite interface.

## 📦 Package

```toml
[dependencies]
Livt.Net = "0.24.1"
```

`Livt.Net` depends on `Livt.IO 0.1.0` for byte-addressable RAM used by the
Ethernet frame I/O path. Domain applications should depend on `Livt.Net`; add
`Livt.IO` directly only when the application also uses I/O primitives itself.

## 📚 Namespaces

Production components live in the shallow `Livt.Net` namespace. Tests use
`Livt.Net.Tests`.

| Area | Components |
|---|---|
| Ethernet | `EthernetFrameParser`, `EthernetFrameBuilder`, `EthernetFrameIo` |
| ARP | `ArpPacketParser`, `ArpResponder` |
| IPv4 | `Ipv4PacketParser`, `Ipv4HeaderBuilder`, `Ipv4HeaderChecksum` |
| ICMP | `IcmpEchoResponder` |
| TCP | `TcpHeaderParser`, `TcpConnectionRecognizer`, `TcpSegmentBuilder`, `TcpSynAckFrameComposer`, `TcpChecksum` |
| HTTP | `HttpGetRecognizer`, `HttpRequestRecognizer`, `HttpResponseGenerator`, `HttpResponseFrameComposer`, `HttpServer` |
| Endpoint | `NetworkEndpoint`, `WebServer` |
| AXI boundary | `IAxi4LiteEthernetLiteMaster`, `Axi4LiteEthernetLiteAdapter` |

## 🔌 API Overview

### Protocol Helpers

Parser components accept fixed-size frame arrays and answer protocol questions
with `bool` return values. Builder and composer components return one byte for a
requested frame index. This one-byte-at-a-time shape keeps offset ownership
explicit and maps cleanly to frame-oriented hardware paths.

Core parser and builder APIs include:

- `IsArp(frame)`, `IsIpv4(frame)`, and MAC byte getters.
- `IsRequest(frame)`, `IsRequestForIpv4(frame, ...)`, and ARP sender getters.
- `IsFixedHeader(frame)`, `IsTcp(frame)`, `IsIcmp(frame)`, and IPv4 byte getters.
- `IsSynOnly(frame)`, `IsAckOnly(frame)`, `IsPshAck(frame)`, and TCP byte getters.
- `GetReplyByte(...)`, `GetResponseHeaderByte(...)`, and `GetFrameByte(...)`.

### Endpoint Flow

`NetworkEndpoint` and `WebServer` use a stateful loaded-frame pattern:

1. `BeginFrame()`
2. `LoadRxByte(index, value)` for each received byte
3. `HandleFrame()`
4. `HasResponse()`
5. `GetResponseLength()` and `GetResponseByte(index, httpBodyByte)`

Response kind and diagnostic getters expose what the endpoint selected for the
last handled frame.

### HTTP

HTTP support is intentionally small:

- HTTP/1.0 `GET` recognition.
- fixed route configuration through `SetRoutePath(route, path)`.
- externally supplied HTTP body bytes.
- body length and checksum metadata supplied through `SetBodyConfig(route,
  length, checksumWordSum)`.

The current route path API stores up to six path bytes and is used by the
existing root and `/about` route tests.

### EthernetLite Boundary

`EthernetFrameIo` owns RX/TX frame buffers and drives an AXI4-Lite
EthernetLite-style interface through `IAxi4LiteEthernetLiteMaster`. It exposes
frame-level helpers such as `LoadRxByte`, `SubmitRxFrame`, `BeginTxFrame`,
`WriteTxByte`, and `SubmitTxFrame`.

## 🧪 Build and Test

```sh
livt test
```

The configured test list is defined in [`livt.toml`](livt.toml). Usage examples
live in [`docs/usage.md`](docs/usage.md). Hardware and protocol notes live in
[`docs/hardware-notes.md`](docs/hardware-notes.md). Package boundary and design
notes live in [`docs/design-notes.md`](docs/design-notes.md).

## 🛠️ Development Notes

- Keep reusable protocol components in `namespace Livt.Net`.
- Keep application-specific content, routing policy, and board integration in
  application packages.
- Prefer `byte` for frame bytes and `logic[N]` for hardware signals.
- Keep parser, recognizer, builder, and responder responsibilities separate.
- Keep constructors for wiring and endpoint configuration; use explicit calls
  for computed startup work.
- Document compiler workarounds only when they remain reproducible.

## 🚧 Outlook

Likely future package work includes domain folders with mirrored test folders,
configurable frame-buffer sizes, broader IPv4/TCP option handling, UDP support,
streaming response adapters, and cleaner separation between protocol library
components and application-facing web-server examples.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
