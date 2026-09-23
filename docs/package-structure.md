# Package structure and helper APIs

The public protocol namespace remains `Livt.Net`. Protocol names already identify
Ethernet, IPv4, ARP, ICMP and TCP, so callers do not need a separate import for
each header in a composition. Device-specific names remain in
`Livt.Net.Drivers.EthernetLite`.

| Source directory | Responsibility |
|---|---|
| `packet` | Bounded byte providers, regions, cached headers, result types and `NetworkOrder` |
| `ethernet` | Ethernet envelopes, parsing, encoding and `IEthernetPayload` |
| `ipv4` | IPv4 envelopes, parsing, encoding, fixed-header checksum and `IIpv4Payload` |
| `arp` | ARP parsing, reply fields and response preparation |
| `icmp` | ICMP echo reply composition and response preparation |
| `tcp` | TCP parsing, recognition, fixed-header encoding/checksum and SYN-ACK composition |
| `checksum` | General one's-complement folding and stateful stream accumulation |
| `services` | Acceptance policies, protocol dispatch and coordinated response ownership |
| `link` | Device-independent RX/TX contracts and deterministic test links |
| `drivers/ethernetlite` | EthernetLite transactions, buffering, driver ownership and AXI pins |

## Pure calculations and stateful components

`NetworkOrder`, `ChecksumArithmetic`, `Ipv4HeaderChecksum`, `TcpChecksum`,
`EthernetFrameBuilder`, `Ipv4HeaderBuilder` and `TcpSegmentBuilder` are classes
with context-free static functions. Do not instantiate them. They neither borrow
packet providers nor start scheduled component transactions.

`InternetChecksum` remains a component because it owns an accumulated sum and a
pending octet. Providers, parsers, prepared packets, response services and link
owners also remain components: their state and lifetimes are part of their role.
The bounded SYN-ACK composer remains a scheduled composition entry point with a
compile-time request capacity; its byte encoders no longer need child instances.

Packet data and emitted octets use `byte`. The driver boundary uses `logic` vectors
for hardware signals. Lengths and decoded 16-bit words use `int` with documented
bounds; decoded 32-bit sequence numbers use `uint`. Addresses, ports and serialized
sequence fields use fixed byte arrays in network order. These small value arrays
are metadata, not unbounded request frames or substitute packet providers.

EtherType constants are declared on `IEthernetPayload`; IPv4 protocol octets are
on `IIpv4Payload`. Envelopes, responders and service classification share these
identities. Protocol-relative field offsets and fixed-header sizes remain local
to the format that interprets them. RX parse results, service outcomes and link
completion states retain their separate enums because they describe different
operations.

## Header encoding

Extract validated endpoint metadata through parsers, then call the pure encoders:

```livt
var destinationMac: byte[6] = [0x02, 0x10, 0x20, 0x30, 0x40, 0x50]
var sourceMac: byte[6] = [0x00, 0x00, 0x5E, 0x00, 0xFA, 0xCE]
var octet = EthernetFrameBuilder.GetByte(12, sourceMac, destinationMac,
    IEthernetPayload.ETHER_TYPE_IPV4)
```

The Ethernet encoder accepts an `int` EtherType. The IPv4 encoder accepts total
length, identification, source/destination addresses, protocol and checksum. The
TCP encoder accepts source/destination ports, sequence, acknowledgment, flags,
window and checksum. All return `byte`; out-of-header indices return zero.
Their documented input bounds are preconditions, not packet-validation results.
Use the checked packet components when preparing a complete published response.

The encoders no longer parse fixed offsets out of request arrays or implicitly
swap endpoints. Reply direction is explicit at the composition root. Existing
TCP/HTTP composers retain their bounded request input, extract the relevant
metadata, and call these encoders. Prepared ARP/ICMP packet graphs and response
ownership are unchanged.

## Migration

- Replace checksum component fields and constructors with static calls.
- Use `Ipv4HeaderChecksum.Calculate(totalLength, identification, sourceIp,
  destinationIp, protocol)`; total length is an integer, not split octets.
- Use `TcpChecksum.CalculateFixedHeaderChecksum` or `CalculatePayloadChecksum`
  with address, port, sequence and acknowledgment arrays. Scalar-octet and
  `FromBytes` duplicate APIs are removed.
- Use `NetworkOrder.Word(high, low)` to decode a word and `HighByte`/`LowByte`
  to encode a word in 0..65535. `ByteValue` interprets an octet as 0..255.
  These replace repeated conversion methods on checksum components.
- Pass actual `byte` data to `InternetChecksum.AddByte`. Convert a hardware logic
  vector explicitly at the boundary.
- Replace builder instances and `GetReplyHeaderByte`/`GetResponseHeaderByte`
  calls with the corresponding static `GetByte` and explicit metadata.

No compatibility wrappers are retained. Static extraction preserves the tested
packet bytes and checksum values; it does not promise identical cycle counts or
hardware costs. Verification uses Livt tests, with no synthesis requirement.

Common inherited specializations live beside their protocols. See
[common packet compositions](common-packets.md) for exact expansions, supported
defaults, construction and lifetime rules.
