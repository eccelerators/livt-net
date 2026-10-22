# IPv4 UDP

Livt.Net 1.3.0 adds UDP composition and parsing in `namespace Livt.Net`.
The application supplies endpoint addresses, payload storage and transmission
policy. Video formats, frame scheduling and media arbitration remain in the
application.

## Choose the component

| API | Responsibility |
|---|---|
| `UdpEthernetPacket<P: IPacketData>` | Prepare a complete Ethernet/IPv4/UDP frame over a borrowed payload |
| `UdpPacketParser<S: IPacketData>` | Validate an IPv4 UDP packet and expose its bounded payload |
| `UdpHeader.GetByte` | Calculate one Ethernet/IPv4/UDP header octet from explicit metadata |
| `UdpChecksum.Calculate` | Calculate the UDP checksum from endpoint metadata and a payload word sum |

The packet and parser are stateful components. Header and checksum helpers are
pure static calculations. Use the prepared packet for ordinary scheduled work;
use the header helper when a custom datapath needs explicit emission scheduling.
Neither choice promises a particular hardware cost or throughput.

## Prepare a datagram

Wire the payload and packet in the owning component's constructor. For example,
these are member declarations and constructor assignments, with endpoint arrays
supplied by the owner:

```livt
// Small bounded payload storage; use RamPacketData for RAM-backed storage.
payload: ArrayPacketData<32>
packet: UdpEthernetPacket<ArrayPacketData<32>>

new(localMac: byte[6], localIp: byte[4], remoteMac: byte[6], remoteIp: byte[4])
{
    this.payload = new ArrayPacketData<32>()
    this.packet = new UdpEthernetPacket<ArrayPacketData<32>>(
        this.payload, localMac, localIp, remoteMac, remoteIp)
}
```

With a fresh or released payload, the following test-style sequence publishes
three bytes and prepares a checksummed datagram. Production callers handle
unsuccessful results according to their retry/drop policy.

```livt
assert this.payload.TryWrite(0, 0x80) == PacketDataResult.Success
assert this.payload.TryWrite(1, 0xFE) == PacketDataResult.Success
assert this.payload.TryWrite(2, 0x01) == PacketDataResult.Success
assert this.payload.TryPublish() == PacketDataResult.Success
assert this.packet.PrepareChecksummed(1234, 5678, 0x1234)
assert this.packet.GetAvailableLength() == 60
```

Bind a frame transmitter to `packet` and submit it using the transmitter's
normal lifecycle. Keep the payload and all four address arrays stable from
preparation through terminal transmission completion, including any dependent
reads. After acknowledging completion, release the packet before its payload:

```livt
this.packet.Release()
assert this.payload.TryRelease() == PacketDataResult.Success
```

`Release()` invalidates the prepared view; it does not cancel an active MAC
transfer or release the payload. A rejected submission has no transmitter borrow,
but the prepared view must still be released before its dependencies are reused.
One owner serializes preparation, transmission and release.

`Prepare` and `PrepareChecksummed` return false for an overlapping publication,
unavailable payload, payload length outside 0..1472, source port outside
0..65535, destination port outside 1..65535, or identification outside 0..65535.
A payload read failure during checksum calculation also leaves the packet
unpublished. A failed overlapping call does not discard the existing publication.

The packet emits a fixed 20-byte IPv4 header with DF set and TTL 64, followed by
an 8-byte UDP header. It pads short Ethernet frames with zeros to 60 bytes,
excluding preamble and FCS. The MAC supplies those wire-level fields.

## Receive a datagram

`UdpPacketParser<S>` takes a source whose byte zero is the **IPv4 header**.
For an Ethernet capture, bind it to the payload view of `EthernetFrameParser<S>`
and check EtherType before invoking UDP parsing. Do not bind it to a payload view
that already skips the IPv4 header.

For an IP-only published provider, construction is:

```livt
// Bounded input storage for a complete IPv4 packet in this example.
input: ArrayPacketData<64>
parser: UdpPacketParser<ArrayPacketData<64>>

new()
{
    this.input = new ArrayPacketData<64>()
    this.parser = new UdpPacketParser<ArrayPacketData<64>>(this.input)
}
```

After filling and publishing the input, call `TryParse()` and require
`PacketParseResult.Success` before using `GetSourcePort()`,
`GetDestinationPort()`, `HasChecksum()`, `GetAvailableLength()` or `TryRead()`.
`TryRead(0, value)` now reads the first UDP **payload** byte. The parser validates:

- Fixed IPv4 header, its checksum and protocol 17.
- Complete declared IPv4 packet and UDP header.
- UDP length of at least eight bytes, equal to the declared IPv4 payload length.
- Every nonzero UDP checksum, including the IPv4 pseudo-header and full payload.

A wire-zero UDP checksum is accepted as omitted. IPv4 options and fragments are
unsupported. Malformed lengths/checksums are invalid, incomplete packets are
truncated, and unavailable borrowed data is not ready. Failed parsing clears
previous metadata; check status rather than interpreting zero-valued getters as
valid endpoint information.

Keep the input published/acquired and unchanged through parsing and payload
consumption. Call `parser.Invalidate()` before releasing or replacing its source;
invalidate descendants before the enclosing Ethernet view. Endpoint filtering
and port dispatch remain application policy.

## Checksum and scheduling

`Prepare(sourcePort, destinationPort, identification)` deliberately emits a zero
UDP checksum. `PrepareChecksummed(...)` reads the payload through
`InternetChecksum` and publishes only when the checksum is ready. Both calculate
the IPv4 header checksum. Checksum scanning takes scheduled work proportional to
payload length and provider latency; neither preparation nor parsing promises
one-cycle completion.

For a custom emitter, call:

```livt
var checksum = UdpChecksum.Calculate(sourceIp, destinationIp,
    sourcePort, destinationPort, udpLength, payloadWordSum)
```

Here `udpLength` includes the eight-byte UDP header (8..65515), and
`payloadWordSum` comes from `InternetChecksum.GetWordSum()` after feeding exactly
the payload bytes. Odd payload lengths include a zero low octet in the final
word. The helper encodes a computed checksum of zero as `0xFFFF`, because wire
zero means omitted. These are caller preconditions for the pure helper; use the
packet component for checked preparation within the Ethernet MTU.

`UdpHeader.GetByte(index, localMac, localIp, remoteMac, remoteIp, payloadLength,
identification, checksum, sourcePort, destinationPort, udpChecksum)` emits header
indices 0..41. `identification` is `uint`; the other numeric arguments are `int`.
`checksum` is the IPv4 header checksum. The caller validates metadata, supplies
both checksums and keeps the address arrays stable. The helper adds no payload,
padding or FCS; out-of-header indices return zero.

Ethernet CRC32/FCS and the UDP Internet checksum are separate operations.
`EthernetLiteReceiveWindow` uses `Livt.IO.EthernetCrc.Update` for its CRC scan;
UDP uses `InternetChecksum` and `UdpChecksum`.

## Scope and validation

There is no IPv6, fragment reassembly, automatic ARP resolution, UDP retransmission
or port dispatcher in these components. Configure or resolve the destination MAC
before transmission. Unlike the transmit wrapper's 1472-byte payload limit, the
parser's captured length is bounded by its provider and the validated IPv4/UDP
lengths.

[`UdpPacketTest`](../tests/UdpPacketTest.lvt) is the executable example: independent
wire vectors cover checked and omitted checksums, odd and empty payloads,
computed-zero encoding, malformed/truncated input, padding and publication reuse.
See [release validation](design-notes.md#ipv4-udp-and-networking-refactor-validation-2026-10-22)
for the full suite's unresolved baseline failures and integration results.
