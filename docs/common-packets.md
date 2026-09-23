# Common packet compositions

Use short names for supported combinations, and explicit composition for custom
protocols. A `Packet` starts at the IPv4 header; a `Frame` includes the Ethernet
header and minimum-frame padding, excluding preamble and FCS.

| Name | Inherited implementation | Constructor |
|---|---|---|
| `TcpIpv4Packet<P>` | `Ipv4Packet<TcpSegment<P>>` | `new(segment)` |
| `TcpIpv4Frame<P, MAX_PAYLOAD_LENGTH = 1500>` | `EthernetFrame<TcpIpv4Packet<P>, MAX_PAYLOAD_LENGTH>` | `new(packet)` |
| `ArpReplyFrame` | `EthernetFrame<ArpReply>` | `new(reply)` |
| `Ipv4Frame<P, MAX_PAYLOAD_LENGTH = 1500>` | `EthernetFrame<Ipv4Packet<P>, MAX_PAYLOAD_LENGTH>` | `new(packet)` |
| `IcmpEchoReplyPacket<S>` | `Ipv4Packet<IcmpEchoReply<S>>` | `new(reply)` |
| `IcmpEchoReplyFrame<S, MAX_PAYLOAD_LENGTH = 1500>` | `EthernetFrame<IcmpEchoReplyPacket<S>, MAX_PAYLOAD_LENGTH>` | `new(packet)` |

The ICMP frame borrows the exact named `IcmpEchoReplyPacket<S>`. For an explicitly
constructed `Ipv4Packet<IcmpEchoReply<S>>`, use `Ipv4Frame<IcmpEchoReply<S>>` or
the full `EthernetFrame` type instead.

These are empty inherited specializations, not forwarding components. They reuse
constructors, storage and scheduled methods from their parent components. They
add no payload copies or forwarding calls. This is a source-level statement;
no hardware-cost or cycle-count equivalence is claimed without measurement.

`S` and TCP payload provider `P` must implement `IPacketData`. For the general
`Ipv4Frame<P>`, `P` must additionally implement `IIpv4Payload` so IPv4 can obtain
the protocol number. Required addresses, identification, echo fields
and published data remain explicit. Livt currently supports value-parameter
defaults, but neither type-parameter defaults nor type aliases. Provider types
therefore remain explicit; the standard Ethernet payload limit defaults to 1500.
The name `ArpReplyFrame` selects the existing standard ARP reply implementation.
TCP now has a prepared segment and concise frame composition; see
[TCP construction](tcp-composition.md) for metadata, checksum and lifetime rules.
This adds packet generation, not a general connection-management implementation.

## Common ICMP reply

Fields and construction inside the application component:

```livt
data: ArrayPacketData<128>
reply: IcmpEchoReply<ArrayPacketData<128>>
packet: IcmpEchoReplyPacket<ArrayPacketData<128>>
frame: IcmpEchoReplyFrame<ArrayPacketData<128>>

new()
{
	data = new ArrayPacketData<128>()
	reply = new IcmpEchoReply<ArrayPacketData<128>>(data)
	packet = new IcmpEchoReplyPacket<ArrayPacketData<128>>(reply)
	frame = new IcmpEchoReplyFrame<ArrayPacketData<128>>(packet)
}
```

Publish the initialized data prefix, then prepare the children before their
parents. In an application function, with explicit network-order address and
identification arguments:

```livt
var result = reply.TryPrepare(identifier, sequence)

if (result == PacketDataResult.Success) {
	result = packet.TryPrepare(sourceIp, destinationIp, identification)
}

if (result == PacketDataResult.Success) {
	result = frame.TryPrepare(sourceMac, destinationMac)
}
```

Read the frame only after Success, check each `TryRead` result, and use
`GetAvailableLength()` for the padded Ethernet length. RAM-backed echo data uses
`RamPacketData<N>` in the same three type arguments. A custom provider is equally
valid; the convenience type does not allocate or select its storage.

For an ARP reply, construct `ArpReply` and `ArpReplyFrame(reply)`, prepare the reply
with source/target MAC and IPv4 addresses, then prepare the frame with source and
destination MAC addresses. All input metadata remains explicit.

## Custom packet generator

A user-defined `MyProtocolPayload` implements `IPacketData` and `IIpv4Payload`.
It publishes its own data and reports its protocol number via `GetProtocol()`.
The fully explicit composition remains available:

```livt
payload: MyProtocolPayload
packet: Ipv4Packet<MyProtocolPayload>
frame: EthernetFrame<Ipv4Packet<MyProtocolPayload>>

new()
{
	payload = new MyProtocolPayload()
	packet = new Ipv4Packet<MyProtocolPayload>(payload)
	frame = new EthernetFrame<Ipv4Packet<MyProtocolPayload>>(packet)
}
```

`Ipv4Frame<MyProtocolPayload>` is an optional shorter envelope name. Custom
Ethernet protocols can instead implement `IEthernetPayload` and use
`EthernetFrame<MyEthernetPayload>`, without an IPv4 layer. Neither form needs a
connection service, AXI adapter or EthernetLite driver. The generic payload
contract supplies a protocol identity; it does not implement that protocol's
validation or transport checksum on behalf of a custom leaf.

## Preparation and lifetime

All graphs start unprepared. Preparation is scheduled and may read the provider;
failed preparation clears that component's previous readiness. There is no
atomic preparation of the whole graph and no automatic invalidation of parents.
Before replacing data, finish every reader and TX borrow, invalidate frame,
packet and reply in that order, then release/repopulate the provider. Prepare
again from the provider outward and stop on the first failure. An owner must
never publish an old outer frame after a child preparation fails.

Use one serialized owner in the same clock/reset context. Short names inherit
all bounds, read errors and readiness behavior of the explicit graph. The frame
payload limit includes the IPv4 header; IP total length excludes Ethernet
padding. A convenience frame does not itself reserve a transmitter or manage a
connection. Use the existing checked responders/services when request recognition
and coordinated response ownership are needed.
