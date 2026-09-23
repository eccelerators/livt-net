# Livt.Net

`Livt.Net` provides compile-time configurable networking components for Livt hardware designs.
It focuses on small request/response stacks that can parse Ethernet frames,
classify common IPv4 traffic, and emit deterministic response bytes.

The 1.1.0-dev package surface is intentionally narrow and hardware-oriented:

- `Livt.Net.EthernetFrameParser`: fixed Ethernet II header parser.
- `Livt.Net.EthernetFrameBuilder`: Ethernet reply-header byte builder.
- `Livt.Net.ArpPacketParser`: ARP packet parser for Ethernet/IPv4 frames.
- `Livt.Net.ArpResponder`: ARP request recognition and prepared reply composition.
- `Livt.Net.Ipv4PacketParser`: bounded fixed-header IPv4 parser.
- `Livt.Net.Ipv4HeaderBuilder`: IPv4 response-header byte builder.
- `Livt.Net.Ipv4HeaderChecksum`: checksum helper for fixed IPv4 responses.
- `Livt.Net.InternetChecksum`: streaming RFC 1071 Internet checksum helper.
- `Livt.Net.IcmpEchoResponder`: ICMP request recognition and prepared reply composition.
- `Livt.Net.TcpHeaderParser`: bounded TCP header parser.
- `Livt.Net.TcpConnectionRecognizer`: TCP packet recognizer for local endpoints.
- `Livt.Net.TcpSegmentBuilder`: TCP response-header byte builder.
- `Livt.Net.TcpSynAckFrameComposer`: Ethernet/IPv4/TCP SYN-ACK frame composer.
- `Livt.Net.TcpChecksum`: checksum helper for fixed TCP responses.
- `Livt.Net.IFrameReceiver` / `IFrameTransmitter`: device-independent frame capabilities.
- `Livt.Net.Drivers.EthernetLite`: concrete driver, ownership components and AXI boundary.

## 📦 Package

```toml
[dependencies]
Livt.Net = "1.1.0-dev"
```

`Livt.Net` depends on `Livt.IO 1.2.0-dev` for byte-addressable RAM used by the
Ethernet frame I/O path. Domain applications should depend on `Livt.Net`; add
`Livt.IO` directly only when the application also uses I/O primitives itself.

## 📚 Namespaces

Protocol and frame-capability components live in `Livt.Net`. The concrete
EthernetLite implementation lives in `Livt.Net.Drivers.EthernetLite`; application
protocol code need not import it. Tests use `Livt.Net.Tests`.

| Area | Components |
|---|---|
| Packet data | `IPacketData`, `ArrayPacketData`, `RamPacketData`, `PacketRegion` |
| Ethernet | `EthernetFrame`, `EthernetFrameParser`, `EthernetFrameBuilder` |
| ARP | `ArpPacketParser`, `ArpReply`, `ArpResponder` |
| IPv4 | `Ipv4Packet`, `Ipv4PacketParser`, `Ipv4HeaderBuilder`, `Ipv4HeaderChecksum` |
| ICMP | `IcmpEchoReply`, `IcmpEchoResponder` |
| TCP | `TcpHeaderParser`, `TcpConnectionRecognizer`, `TcpSegmentBuilder`, `TcpSynAckFrameComposer`, `TcpChecksum` |
| Checksums | `InternetChecksum`, `Ipv4HeaderChecksum`, `TcpChecksum` |
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
and migration from the old responder byte APIs.

### Protocol Helpers

Parsers bind `IPacketData` providers and expose checked, bounded payload views.
Compose Ethernet → IPv4 → TCP, or parse a protocol directly from a region.
`TryParse()` distinguishes complete structure, partial capture, unsupported
formats and malformed headers. Getters expose decoded metadata rather than
individual high/low field bytes. See [bounded packet parsing](docs/packet-parsing.md)
for supported forms, checksum policy and lifetime rules.

Responders bind a frame provider and use `TryPrepare(localMac, localIp)`, followed
by `TryRead(index, value)` and `GetAvailableLength()`. Existing TCP builders and
composers retain their emission API; the common service covers ARP/ICMP.

`InternetChecksum` incrementally consumes network-order bytes with `AddByte()`.
It returns either the unfolded word sum for use with `TcpChecksum` or the final
RFC 1071 checksum, including the required zero padding for odd-length input.

### Buffered link capabilities

`IFrameReceiver` provides acquired, bounded RX data. `IFrameTransmitter` borrows
a prepared source through terminal completion. `TestFrameReceiver` and
`TestFrameTransmitter` provide deterministic Livt test implementations. See
[buffered frame links](docs/frame-link.md) for ownership, results and test controls.
The concrete implementation is in `Livt.Net.Drivers.EthernetLite`; see the
[driver contract and construction example](docs/ethernetlite.md).

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

### Compile-time configuration

Parser type parameters select `IPacketData` providers; their payloads compose as
bounded regions. Storage components select capacity, independently of protocol
layout. The EthernetLite receiver defaults to 128 bytes (supported 60..1514), and
its transmitter accepts prepared standard frames of 60..1514 bytes by default.
The final partial AXI word is zero-filled without reading past the source.

## Development verification status

Use Livt tests for the driver and consumers. Prior native AXI/board evidence
belongs to the former implementation and is not verification of the extracted
driver. Simulation does not establish FPGA timing or board readiness.

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
