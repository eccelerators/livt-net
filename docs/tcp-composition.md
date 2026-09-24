# Prepared TCP packet composition

`TcpSegment<P: IPacketData>` emits a fixed 20-byte TCP header followed by a
published payload. It implements `IPacketData` and `IIpv4Payload`. This is packet
construction, with no connection state, retransmission, options or congestion
control. The urgent pointer is zero; callers choose sequence/acknowledgment,
flags, ports and advertised window explicitly.

```livt
data: RamPacketData<1024>
segment: TcpSegment<RamPacketData<1024>>
packet: TcpIpv4Packet<RamPacketData<1024>>
frame: TcpIpv4Frame<RamPacketData<1024>>

new()
{
    this.data = new RamPacketData<1024>()
    this.segment = new TcpSegment<RamPacketData<1024>>(this.data)
    this.packet = new TcpIpv4Packet<RamPacketData<1024>>(this.segment)
    this.frame = new TcpIpv4Frame<RamPacketData<1024>>(this.packet)
}
```

At runtime, populate and publish `data`, then prepare children before parents:

```livt
var result = segment.TryPrepare(sourceIp, destinationIp, sourcePort,
    destinationPort, sequence, acknowledgment, flags, window)
if (result != PacketDataResult.Success) { return }
result = packet.TryPrepare(sourceIp, destinationIp, identification)
if (result != PacketDataResult.Success) { return }
result = frame.TryPrepare(sourceMac, destinationMac)
if (result != PacketDataResult.Success) { return }
```

All metadata arrays use network order: addresses are byte[4]/byte[6], ports and
window byte[2], sequence/acknowledgment byte[4], flags byte. Use the **same IPv4
addresses** for TCP preparation and its enclosing IP packet: they are included
in the TCP pseudo-header checksum. Ethernet addresses may differ independently.

`TcpIpv4Packet<P>` is `Ipv4Packet<TcpSegment<P>>`; `TcpIpv4Frame<P>` inherits
`EthernetFrame<TcpIpv4Packet<P>>` and borrows that exact named child. Both are
empty specializations. Explicit `EthernetFrame<Ipv4Packet<TcpSegment<P>>>`
composition remains available; use consistent exact child types in constructors.
The frame's optional payload limit defaults to 1500.

## Bounds and lifetime

TCP accepts payload lengths 0..65495, allowing a 65535-byte IPv4 packet. The
standard Ethernet envelope imposes its smaller payload limit. Empty published
providers generate header-only segments such as SYN-ACK. Preparation reads the
complete payload once, propagates read failures and computes the checksum from
actual bytes (including odd final octets). No supplied checksum or assumed body
sum is trusted. The maximum permitted input keeps the unfolded checksum sum
within a signed int. The pseudo-header, zero-checksum TCP header and payload
are accumulated by scheduled `InternetChecksum.AddByte` calls. Preparation
spreads the arithmetic across cycles and then patches the two checksum bytes;
it does not place the complete TCP sum in one combinational expression.

`TryPrepare` invalidates prior segment metadata before checking the new input.
Unprepared reads return NotReady; out-of-range reads return Invalid. Successful
preparation caches only the header and length; later payload reads still delegate
to the provider and propagate its failures. Treat output bytes as data only on
Success. There is no extra payload copy and no fixed-cycle performance promise.

The owner must preserve the payload and prepared ancestors throughout reads and
TX borrowing. Finish TX completion/acknowledgment, invalidate frame then packet
then segment, and finally release or replace the provider. Invalidating a child
behind a prepared parent violates this ownership contract.

## Consumer migration

The specialized raw-request `TcpSynAckFrameComposer` is removed. Publish an empty
provider and prepare this same graph with SYN-ACK metadata. The old per-byte
HTTP frame composer and caller-supplied checksum API are also replaced; Web binds
content and prepares a composed frame before any response reads. These changes
intentionally require matching development Web and WebApp sources.
