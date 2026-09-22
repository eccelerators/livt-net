# Livt.Net

`Livt.Net` provides compile-time configurable networking components for Livt hardware designs.
It focuses on small request/response stacks that can parse Ethernet frames,
classify common IPv4 traffic, and emit deterministic response bytes.

The 1.1.0-dev package surface is intentionally narrow and hardware-oriented:

- `Livt.Net.EthernetFrameParser`: fixed Ethernet II header parser.
- `Livt.Net.EthernetFrameBuilder`: Ethernet reply-header byte builder.
- `Livt.Net.ArpPacketParser`: ARP packet parser for Ethernet/IPv4 frames.
- `Livt.Net.ArpResponder`: ARP reply selector and byte builder.
- `Livt.Net.Ipv4PacketParser`: fixed 20-byte IPv4 header classifier.
- `Livt.Net.Ipv4HeaderBuilder`: IPv4 response-header byte builder.
- `Livt.Net.Ipv4HeaderChecksum`: checksum helper for fixed IPv4 responses.
- `Livt.Net.InternetChecksum`: streaming RFC 1071 Internet checksum helper.
- `Livt.Net.IcmpEchoResponder`: ICMP echo reply selector and byte builder.
- `Livt.Net.TcpHeaderParser`: fixed 20-byte TCP header classifier.
- `Livt.Net.TcpConnectionRecognizer`: TCP packet recognizer for local endpoints.
- `Livt.Net.TcpSegmentBuilder`: TCP response-header byte builder.
- `Livt.Net.TcpSynAckFrameComposer`: Ethernet/IPv4/TCP SYN-ACK frame composer.
- `Livt.Net.TcpChecksum`: checksum helper for fixed TCP responses.
- `Livt.Net.EthernetFrameIo`: frame buffer and AXI4-Lite EthernetLite boundary.
- `Livt.Net.Axi4LiteEthernetLiteAdapter`: AXI4-Lite EthernetLite signal adapter.
- `Livt.Net.IAxi4LiteEthernetLiteMaster`: AXI4-Lite EthernetLite interface.

## 📦 Package

```toml
[dependencies]
Livt.Net = "1.1.0-dev"
```

`Livt.Net` depends on `Livt.IO 1.2.0-dev` for byte-addressable RAM used by the
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
| Checksums | `InternetChecksum`, `Ipv4HeaderChecksum`, `TcpChecksum` |
| AXI boundary | `IAxi4LiteEthernetLiteMaster`, `Axi4LiteEthernetLiteAdapter` |

## 🔌 API Overview

### Protocol Helpers

Parser components accept compile-time-sized frame arrays and answer protocol questions
with `bool` return values. Builder and composer components return one byte for a
requested frame index. This one-byte-at-a-time shape keeps offset ownership
explicit and maps cleanly to frame-oriented hardware paths.

Core parser and builder APIs include:

- `IsArp(frame)`, `IsIpv4(frame)`, and MAC byte getters.
- `IsRequest(frame)`, `IsRequestForIpv4(frame, ...)`, and ARP sender getters.
- `IsFixedHeader(frame)`, `IsTcp(frame)`, `IsIcmp(frame)`, and IPv4 byte getters.
- `IsSynOnly(frame)`, `IsAckOnly(frame)`, `IsPshAck(frame)`, and TCP byte getters.
- `GetReplyByte(...)`, `GetResponseHeaderByte(...)`, and `GetFrameByte(...)`.

`InternetChecksum` incrementally consumes network-order bytes with `AddByte()`.
It returns either the unfolded word sum for use with `TcpChecksum` or the final
RFC 1071 checksum, including the required zero padding for odd-length input.

### Endpoint Flow

`EthernetFrameIo` uses a complete-frame ownership contract:

1. Poll `IsFrameAvailable()`, copy the captured RX bytes with `GetRxByte()`,
   then call `ConsumeRxFrame()`.
2. Call `TryBeginTxFrame(length)` and check its result.
3. Write bytes in ascending order with `TryWriteTxByte(index, value)`.
4. Call `TrySubmitTxFrame()` after every declared byte has been written.
5. Wait until `HasTxFrame()` is false before beginning another transmission.

`HasSentFrameToAxi()` means delivery to the device, not physical transmission.
The legacy void TX methods remain available and ignore rejected operations.
For simulation injection, use `LoadRxByte()` to initialize the entire RX capture
in ascending order, then `SubmitRxFrame()`; do not inject during hardware RX.

### Compile-time configuration

Frame-consuming helpers accept `FRAME_CAPACITY`: Ethernet parsing and ARP default
to 64 bytes; other helpers default to 128. For example,
`TcpConnectionRecognizer<256>` and its child parsers all use `byte[256]`.
Classifiers accept an optional final `validLength` argument; pass the received
length to reject truncated headers. Omitting it declares the whole array valid.
The default is `FRAME_CAPACITY` from that parser's concrete specialization.

`EthernetFrameIo<RX_CAPACITY = 128, RX_STORAGE_CAPACITY = 2048,
TX_STORAGE_CAPACITY = 2048>` separates captured bytes from RAM depth. RX capture
must be a positive multiple of four, at most 2036, and fit its storage. Storage
capacities are positive and at most 2048. TX length is limited by both its storage
and the 2036-byte data area below the EthernetLite length register.

RAM cells are unspecified until written and survive reset. Frame metadata makes
old data unavailable; submission rejects incomplete frames and out-of-order
writes that leave holes. Final AXI word padding is explicitly zero.

### EthernetLite Boundary

`EthernetFrameIo` owns RX/TX frame buffers and drives an AXI4-Lite
EthernetLite-style interface through `IAxi4LiteEthernetLiteMaster`. It exposes
frame-level helpers such as `LoadRxByte`, `SubmitRxFrame`, `BeginTxFrame`,
`WriteTxByte`, and `SubmitTxFrame`.

## Development verification status

The Livt behavioral suite passes, and native AXI verification passes across
debug/release, optimization and reset variants with the #491 compiler fix.
Invalid generic capacities are rejected by both validation and build with the
#492 compiler fix. Development web-app integration is verified with #497; see
[consumer evidence](../livt-web-app/verification/migration-evidence.md).
Simulation does not establish FPGA timing or board readiness. See
[verification evidence](docs/migration-evidence.md) before hardware integration.

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
broader IPv4/TCP option handling, UDP support, and streaming frame adapters.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
