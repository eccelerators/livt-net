# Livt.Net Usage

## Parse a configured capture

Bind `EthernetFrameParser<ArrayPacketData<256>>` to a published provider, call
`TryParse()`, and check `IsReady()` and `GetEtherType()`. Compose an
`Ipv4PacketParser` over that parser's bounded payload, or bind it directly to an
IP-only provider. See [packet parsing](packet-parsing.md) for a construction
example, result meanings, metadata and lifetime rules. Storage capacity belongs
to the provider; protocol parsers do not take raw frame arrays or valid lengths.

## Queue a complete response

Prepare an `IPacketData` source such as `RamPacketData`, `EthernetFrame` or a
response component, then call the bound transmitter's `TrySubmit()`. Accepted
borrows the publication until `TryGetCompletion()` reports a terminal result.
Acknowledge completion before another submission. Preserve source and dependent
RX views through that lifetime; rejected submissions never acquire a borrow.

See [EthernetLite construction](ethernetlite.md) for the concrete board adapter.
Application protocol code uses [frame capabilities](frame-link.md), without AXI
or device-specific methods. `EthernetFrameIo` has been replaced without legacy
wrappers. Prepared TX bytes must include minimum-frame Ethernet padding.

## Receive and release

Acquire through `IFrameReceiver.TryAcquire()`, inspect `GetAvailableLength()` and
parse/read only that prefix. Invalidate child views before `TryRelease()`.
EthernetLite reports unknown wire length and excludes retained FCS/tail bytes
with a bounded CRC scan; capacity is not the received length.

Tests use `TestFrameReceiver`: inject initialized bytes then `Publish(known,
length)`. `TestFrameTransmitter` binds a prepared provider; `Advance()` controls
progress and lets a test hold the source borrow. Test injection is not exposed
on the hardware driver.

## Checksum helpers

Checksum calculators are context-free static helpers; do not construct them.
`Ipv4HeaderChecksum.Calculate(totalLength: int, identification: byte[2],
sourceIp: byte[4], destinationIp: byte[4], protocol: byte)` calculates the
fixed 20-byte IPv4 header checksum with version/IHL 0x45, DF and TTL 64.
Use `IIpv4Payload.PROTOCOL_TCP` or `PROTOCOL_ICMP` for the common protocols.

`TcpChecksum.CalculateFixedHeaderChecksum` accepts `(sourceIp: byte[4],
destinationIp: byte[4], sourcePort: byte[2], destinationPort: byte[2],
sequence: byte[4], acknowledgment: byte[4], flags: byte, window: byte[2])`.
`CalculatePayloadChecksum` adds `tcpLength: int` and `payloadWordSum: int`.
Arrays use network order. Length includes the fixed 20-byte TCP header; the
payload sum comes from `InternetChecksum.GetWordSum()`, including a zero low
octet for an odd final byte. The complete unfolded sum must fit a non-negative
int (0..2147483647). Empty payloads use length 20 and sum zero.

`InternetChecksum` retains stream state; reset it before each new stream and
feed `byte` values through `AddByte()`. Use `NetworkOrder.HighByte`/`LowByte` to
serialize a 16-bit checksum and `NetworkOrder.Word` to decode two octets.
The helpers do not add input packet validation. See
[package structure and migration](package-structure.md) for removed APIs and
pure header encoders.

## Packet data providers

Use `ArrayPacketData`, `RamPacketData` and generic `PacketRegion` for checked,
bounded access to published byte prefixes. See [packet data](packet-data.md) for
construction, ownership and release rules.
