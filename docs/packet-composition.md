# Prepared packet composition

Compose byte providers through protocol envelopes:

```livt
payload: RamPacketData<128>
echo: IcmpEchoReply<RamPacketData<128>>
ip: Ipv4Packet<IcmpEchoReply<RamPacketData<128>>>
frame: EthernetFrame<Ipv4Packet<IcmpEchoReply<RamPacketData<128>>>>

new()
{
    payload = new RamPacketData<128>()
    echo = new IcmpEchoReply<RamPacketData<128>>(payload)
    ip = new Ipv4Packet<IcmpEchoReply<RamPacketData<128>>>(echo)
    frame = new EthernetFrame<Ipv4Packet<IcmpEchoReply<RamPacketData<128>>>>(ip)
}
```

These fields belong to one application component in the same clock/reset context.
The provider may instead be `ArrayPacketData` or a `PacketRegion` over another
published source. No envelope stores a full copy of its child packet.

## Preparation and reading

1. Fill the provider with checked writes and publish its initialized prefix.
2. Call `echo.TryPrepare(identifier, sequence)` with network-order `byte[2]` fields.
3. Call `ip.TryPrepare(sourceIp, destinationIp, identification)` with `byte[4]`
   addresses and a network-order `byte[2]` identification.
4. Call `frame.TryPrepare(sourceMac, destinationMac)` with `byte[6]` addresses.
5. Check `PacketDataResult.Success` after each step. Read indices below
   `GetAvailableLength()` using `TryRead(index, value)` and check its result too.

All packet components implement `IPacketData`. `IsReady()` distinguishes prepared
state; unprepared reads return NotReady, invalid indices return Invalid, and
failed read outputs are not usable data. `Invalidate()` clears readiness and
length metadata without modifying the child. A failed preparation clears the
previous prepared response. Child read failures during ICMP checksum preparation
propagate to the caller and leave the reply unprepared.

Preparation and emission are scheduled operations, without a fixed-cycle promise.
ICMP reads its data once during preparation to calculate the checksum. IPv4
calculates its header checksum once. Emission reads prepared headers and delegates
payload bytes. It does not recalculate checksums.

## Ownership

One serialized owner coordinates the graph. Before mutating or replacing a child,
invalidate ancestors from Ethernet inward, then invalidate the ICMP reply and
release its provider (closing any regions first). Prepare again from the leaf
outward. This applies even when the new payload has the same length. There is no
automatic mutation detection or reference counting.

Do not invalidate or reprepare while a transmitter still borrows the response.
Finish all reads and wait for source release before reuse. The current components
do not own a frame-link submission and therefore cannot detect that external
borrow themselves. Reset all participating readers/providers together before
reusing storage. Refer to [packet data](packet-data.md) for provider lifetime rules.

## Protocol boundaries

- `EthernetFrame<P: IPacketData & IEthernetPayload, MAX_PAYLOAD_LENGTH = 1500>`
  accepts a prepared, nonempty payload no larger than its configured limit.
  EtherType must be in 1536..65535. It adds a 14-byte Ethernet II header and pads
  the resulting frame to at least 60 bytes. Preamble and FCS are excluded.
- `Ipv4Packet<P: IPacketData & IIpv4Payload>` emits a fixed 20-byte header,
  DF set, TTL 64 and no options. Payload length must be 1..65515 and protocol
  number 0..255. The IP total length excludes Ethernet padding.
- `IcmpEchoReply<P: IPacketData>` borrows 0..65507 echo-data bytes. It adds the
  eight-byte echo header, uses protocol 1 and calculates the reply checksum from
  the identifier, sequence and actual published data. It does not require or
  trust a checksum supplied by a request.
- `ArpReply` stores only the Ethernet/IPv4 ARP reply metadata. Its
  `TryPrepare(sourceMac, sourceIp, targetMac, targetIp)` builds the 28-byte payload.
  `EthernetFrame<ArpReply>` supplies the same Ethernet header/padding behavior.

Protocol identity is separate from byte access: implement `IEthernetPayload` or
`IIpv4Payload` alongside `IPacketData` for a custom protocol leaf. TCP pseudo-header
checksums, general TCP, streaming and other protocol extensions remain separate.

## Common request/reply API and migration

`ArpResponder<S>` and `IcmpEchoResponder<S, CAPACITY>` own their prepared graphs
bind an Ethernet-frame provider and expose one checked operation:

```livt
var result = responder.TryPrepare(localMac, localIp)
if (result == PacketDataResult.Success) {
    var value: byte = 0x00
    for (var i = 0; i < responder.GetAvailableLength(); i++) {
        if (responder.TryRead(i, value) == PacketDataResult.Success) {
            // Pass value to the application's transmitter.
        }
    }
}
```

The caller publishes the initialized prefix of the constructor-bound provider.
Preparation performs the existing supported request recognition; it is not full
input checksum validation. A nonmatching or truncated request returns Invalid and
clears any prior response. ARP snapshots addresses; ICMP snapshots addresses,
identifiers and echo data. After successful preparation the caller can release and reuse the source,
while keeping the prepared response stable until emission finishes.

This replaces `GetReplyByte(request, index, localMac, localIp)` and
`GetReplyLength(request)`. Prepare once, then use checked reads and the prepared
length. Recognition-only callers use the bounded parsers; `ShouldRespond` and
array-based preparation signatures have been removed. See [packet parsing](packet-parsing.md)
for failure-path invalidation and checksum policy. No old emission signatures or duplicate byte encoders
are retained. The existing TCP builders and composers are unchanged.

Livt.Web's NetworkEndpoint uses the new preparation API and invalidates responses
when beginning another frame. The WebApp consumes that endpoint transitively.
This is a breaking development-package change; update Net and Web together.
For valid ICMP requests the reply bytes are preserved. For inconsistent incoming
ICMP checksum fields, the new response checksum follows the actual bytes instead
of adjusting the supplied field. Incoming checksum validation remains a separate
parser responsibility.
