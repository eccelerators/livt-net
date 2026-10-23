# Livt.Net

`Livt.Net` provides compile-time configurable networking components for Livt hardware designs.
It supports small Ethernet/IPv4 request/response stacks and bounded TCP control
streams, IPv4 UDP datagrams, RAM-backed buffering and a Telnet terminal codec.

The 1.3.1 package surface is intentionally narrow and hardware-oriented:

- `Livt.Net.EthernetFrameParser`: fixed Ethernet II header parser.
- `Livt.Net.EthernetFrameBuilder`: static Ethernet header encoding from explicit addresses.
- `Livt.Net.ArpPacketParser`: ARP packet parser for Ethernet/IPv4 frames.
- `Livt.Net.ArpResponder`: ARP request recognition and prepared reply composition.
- `Livt.Net.Ipv4PacketParser`: bounded fixed-header IPv4 parser.
- `Livt.Net.Ipv4HeaderBuilder`: static fixed IPv4 header encoding.
- `Livt.Net.Ipv4HeaderChecksum`: checksum helper for fixed IPv4 responses.
- `Livt.Net.InternetChecksum`: streaming RFC 1071 Internet checksum helper.
- `Livt.Net.IcmpEchoResponder`: ICMP request recognition and prepared reply composition.
- `Livt.Net.UdpHeader` / `UdpEthernetPacket<P>`: UDP header encoding and prepared Ethernet frames.
- `Livt.Net.UdpChecksum` / `UdpPacketParser<S>`: IPv4 UDP checksum calculation and validated payload views.
- `Livt.Net.TcpHeaderParser`: bounded TCP header parser.
- `Livt.Net.TcpConnectionRecognizer`: TCP packet recognizer for local endpoints.
- `Livt.Net.TcpSegmentBuilder`: static fixed TCP header encoding.
- `Livt.Net.TcpSegment<P>`: prepared TCP segment over a bounded payload provider.
- `Livt.Net.TcpIpv4Packet<P>` / `TcpIpv4Frame<P>`: common TCP packet/frame compositions.
- `Livt.Net.TcpChecksum`: checksum helper for fixed TCP responses.
- `Livt.Net.TcpStreamServer`: bounded passive TCP streams with shared, partitioned RAM storage.
- `Livt.Net.TelnetSession`: bounded Telnet negotiation and terminal-data codec.
- `Livt.Net.IFrameReceiver` / `IFrameTransmitter`: device-independent frame capabilities.
- `Livt.Net.Drivers.EthernetLite`: concrete driver, ownership components and AXI boundary.

## 📦 Package

```toml
[dependencies]
"Livt.Net" = "1.3.1"
```

See the [changelog](CHANGELOG.md) for release changes.

`Livt.Net` depends on `Livt.IO 1.4.0` for byte-addressable RAM used by the
Ethernet frame I/O path. Domain applications should depend on `Livt.Net`; add
`Livt.IO` directly only when the application also uses I/O primitives itself.

Version 1.3.1 documents and verifies the existing IO-MAC adapters over
[MII Ethernet](docs/mii.md) at 10 and 100 Mb/s. No public frame or protocol API
changes are required; PHY management and media timing belong to Livt.IO.

## 📚 Namespaces

Protocol and frame-capability components live in `Livt.Net`. The concrete
EthernetLite implementation lives in `Livt.Net.Drivers.EthernetLite`; application
protocol code need not import it. Tests use `Livt.Net.Tests`. Source folders group
protocol responsibilities without imposing extra imports; see
[package structure and helper APIs](docs/package-structure.md).

| Area | Components |
|---|---|
| Packet data | `IPacketData`, `IWritablePacketData<G>`, `PacketDataGeometry<CAPACITY>`, `ArrayPacketData`, `RamPacketData`, `PacketRegion` |
| Ethernet | `EthernetFrame`, `EthernetFrameParser`, `EthernetFrameBuilder` |
| ARP | `ArpPacketParser`, `ArpReply`, `ArpResponder` |
| IPv4 | `Ipv4Packet`, `Ipv4PacketParser`, `Ipv4HeaderBuilder`, `Ipv4HeaderChecksum` |
| ICMP | `IcmpEchoReply`, `IcmpEchoResponder<S, FRAME_CAPACITY, B>` |
| UDP | `UdpHeader`, `UdpEthernetPacket`, `UdpChecksum`, `UdpPacketParser` |
| TCP packets | `TcpHeaderParser`, `TcpConnectionRecognizer`, `TcpSegmentBuilder`, `TcpSegment`, `TcpIpv4Packet`, `TcpIpv4Frame`, `TcpChecksum` |
| TCP streams | `TcpStreamServer`, `TcpSendBuffer`, `TcpRetryTimer` |
| Telnet | `TelnetSession` |
| Checksums | `InternetChecksum`, `Ipv4HeaderChecksum`, `TcpChecksum`, `UdpChecksum` |
| Services | `NetworkService`, `ArpService`, `IcmpEchoService`, `ServiceChain`, `FrameService`, `ResponseTransfer` |
| Buffered links | `IFrameReceiver`, `IFrameTransmitter`, `TestFrameReceiver`, `TestFrameTransmitter` |
| EthernetLite device | `EthernetLiteDriver`, `EthernetLiteReceiver`, `EthernetLiteTransmitter`, `EthernetLiteBus` |

## 🔌 API Overview

### Network services

`NetworkService` owns the common ARP/ICMP response graphs. Bind a transmitter to
its response source and use `FrameService` to coordinate request handling,
backpressure and terminal cleanup. Custom acceptance strategies and fixed
`ServiceChain` compositions extend the same lifecycle. See
[network services](docs/network-services.md) for construction and ownership.

### Prepared packets

Compose `EthernetFrame<Ipv4Packet<IcmpEchoReply<RamPacketData<128>>>>`
using checked byte providers. Prepare checksums and headers once, then emit
through `IPacketData.TryRead`. ARP reuses `EthernetFrame<ArpReply>`.
See [packet composition](docs/packet-composition.md) for construction, ownership
and response preparation.

### Protocol Helpers

Parsers bind `IPacketData` providers and expose checked, bounded payload views.
Compose Ethernet → IPv4 → TCP, or parse a protocol directly from a region.
`TryParse()` distinguishes complete structure, partial capture, unsupported
formats and malformed headers. Getters expose decoded metadata rather than
individual high/low field bytes. See [bounded packet parsing](docs/packet-parsing.md)
for supported forms, checksum policy and lifetime rules.

Responders bind a frame provider and use `TryPrepare(localMac, localIp)`, followed
by `TryRead(index, value)` and `GetAvailableLength()`. The common service covers ARP/ICMP. TCP packet generators and Web use
[prepared TCP composition](docs/tcp-composition.md), with checksums calculated
from actual payload bytes before emission.

`IcmpEchoResponder<S, FRAME_CAPACITY, B>` owns its writable snapshot backend.
`B` defaults to `RamPacketData<FRAME_CAPACITY>` and may be replaced with
`ArrayPacketData<FRAME_CAPACITY>` or another constructible
`IWritablePacketData<PacketDataGeometry<FRAME_CAPACITY>>`. Capacity is part of the
static contract, and backend selection adds no runtime selector. See
[resource architecture](docs/resource-optimization.md) for storage guidance.

`InternetChecksum` incrementally consumes network-order bytes with `AddByte()`.
It accepts `byte` octets and returns either the unfolded word sum for the static
`TcpChecksum` and `UdpChecksum` helpers or the final
RFC 1071 checksum, including the required zero padding for odd-length input.

### IPv4 UDP

`UdpEthernetPacket<P>` prepares an Ethernet/IPv4/UDP frame over a borrowed
`IPacketData` payload of up to 1472 bytes. Choose `Prepare` to omit the UDP
checksum or `PrepareChecksummed` to calculate it from the payload. Both include
the IPv4 header checksum and minimum Ethernet padding; the MAC supplies FCS.

`UdpPacketParser<S>` validates a complete IPv4 UDP packet, checks any nonzero UDP
checksum, and exposes ports and a bounded payload. Applications own endpoint
selection, destination MAC resolution and transmission scheduling. IPv6,
fragmentation, automatic port dispatch and retransmission are outside this API.
Video framing and streaming remain application responsibilities.
See [UDP construction, ownership and examples](docs/udp.md).

### TCP streams and Telnet

`TcpStreamServer<S, PORT, RX_CAPACITY, TX_CAPACITY, SESSIONS>` provides bounded
passive TCP connections with RAM-backed byte storage, checksum validation, flow
control and retransmission. `SESSIONS` defaults to one and supports up to 16
connections. Connections share parsers and response generation while retaining
independent state and disjoint regions of the receive/transmit RAMs.

`TelnetSession` adapts the byte stream to a minimal NVT terminal protocol with
negotiated echo, CR-LF/CR-NUL input normalization and IAC escaping. These components
target small control streams: one segment is outstanding per connection, graceful
close is peer-initiated, and there is no TCP keep-alive, authentication or encryption.
See [TCP stream ownership and limits](docs/tcp-stream.md).

### Buffered link capabilities

`IFrameReceiver` provides acquired, bounded RX data. `IFrameTransmitter` borrows
a prepared source through terminal completion. `TestFrameReceiver` and
`TestFrameTransmitter` provide deterministic Livt test implementations. See
[buffered frame links](docs/frame-link.md) for ownership, results and test controls.
Production implementations include `Livt.Net.Drivers.EthernetLite` and
`Livt.Net.Drivers.Ethernet` for the portable Livt.IO MAC. See the
[EthernetLite driver](docs/ethernetlite.md) and [IO MAC adapters](docs/ethernet.md)
for construction, backend differences and verification.

### Endpoint flow

1. Acquire RX through `TryAcquire()`, then parse/read only its available prefix.
2. Finish dependent reads and release RX through `TryRelease()`.
3. Prepare/publish a complete response provider, including minimum-frame padding.
4. Submit the transmitter's bound source with `TrySubmit()`.
5. Keep source/dependencies stable until terminal completion, acknowledge the
   result and then release/invalidate the prepared data for reuse.

Responses that still borrow RX postpone step 2 until that dependency ends.
Neither capture capacity nor a protocol-declared length establishes wire length.
EthernetLite publishes a conservative FCS-free prefix and reports length unknown.
The IO MAC adapter exposes a complete FCS-free frame with exact length while acquired.

### Compile-time configuration

Parser type parameters select `IPacketData` providers; their payloads compose as
bounded regions. Storage components select capacity, independently of protocol
layout. The EthernetLite receiver defaults to 128 bytes (supported 60..1514), and
its transmitter accepts prepared standard frames of 60..1514 bytes by default.
The final partial AXI word is zero-filled without reading past the source.

## 🧪 Build and Test

```sh
livt test
```

The configured test list is defined in [`livt.toml`](livt.toml). Usage examples
live in [`docs/usage.md`](docs/usage.md). Hardware and protocol notes live in
[`docs/hardware-notes.md`](docs/hardware-notes.md). Package boundary and design
notes live in [`docs/design-notes.md`](docs/design-notes.md). The package-wide
resource and scheduling rules are recorded in
[`docs/resource-optimization.md`](docs/resource-optimization.md).

The 1.3.0 refactor passed all 18 directly relevant package cases, six demo
packet/streaming cases and board GHDL elaboration/reset. The full suite reported
117 passed, 4 failed and 6 skipped; baseline assertions and a reset timeout remain
unresolved. See [validation details](docs/design-notes.md#ipv4-udp-and-networking-refactor-validation-2026-10-22)
before publishing. No new FPGA resource or timing result is claimed.

## 🛠️ Development Notes

- Keep reusable protocol components in `namespace Livt.Net`.
- Keep application-specific content, routing policy, and platform integration in
  application packages.
- Prefer `byte` for frame bytes and `logic[N]` for hardware signals.
- Keep parser, recognizer, builder, and responder responsibilities separate.
- Keep constructors for wiring and endpoint configuration; use explicit calls
  for computed startup work.

## 🚧 Outlook

Possible future work includes broader IPv4/TCP option handling and
streaming frame adapters. These are separate features, not part of the current
bounded IPv4 request/response and passive TCP stream contracts.

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
