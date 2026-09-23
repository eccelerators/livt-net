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

## Checksum array APIs

`Ipv4HeaderChecksum.CalculateFixedTcpHeaderChecksumFromBytes` and
`CalculateFixedIcmpHeaderChecksumFromBytes` accept `(totalLength: byte[2],
identification: byte[2], localIp: byte[4], remoteIp: byte[4])`.
All arrays use network byte order (high byte first). The generated header uses
version/IHL 0x45, DF, TTL 64 and the selected TCP or ICMP protocol.

`TcpChecksum.CalculateFixedHeaderChecksumFromBytes` accepts `(localIp: byte[4],
remoteIp: byte[4], localPort: byte[2], remotePort: byte[2], sequence: byte[4],
acknowledgment: byte[4], flags: byte, window: byte[2])`.
`CalculatePayloadChecksumFromBytes` accepts the same fields followed by `tcpLength: int`
and `payloadWordSum: int`. Length includes the fixed 20-byte TCP header; the sum
is from `InternetChecksum.GetWordSum()`, with an odd final byte treated as the
high byte of a word whose low byte is zero. The complete unfolded sum must fit
in a non-negative int (0..2147483647). Empty payloads use length 20 and sum zero.

Existing scalar methods retain their original names and remain available; scalar byte fields must be 0..255.
Both API shapes share the same checksum arithmetic. The array APIs do not
add protocol validation or change supported packet formats.

## Packet data providers

Use `ArrayPacketData`, `RamPacketData` and generic `PacketRegion` for checked,
bounded access to published byte prefixes. See [packet data](packet-data.md) for
construction, ownership and release rules.
