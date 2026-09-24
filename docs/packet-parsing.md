# Bounded packet parsing

Parsers bind an `IPacketData` component at construction. The input starts at that
protocol's header, so an IPv4 parser can read an IP packet directly, an Ethernet
parser's payload, or a `PacketRegion` at any offset. No public parser accepts a
raw frame array or a separate caller-supplied valid length.

```livt
source: RamPacketData<256>
ethernet: EthernetFrameParser<RamPacketData<256>>
ipv4: Ipv4PacketParser<EthernetFrameParser<RamPacketData<256>>>

new()
{
	source = new RamPacketData<256>()
	ethernet = new EthernetFrameParser<RamPacketData<256>>(source)
	ipv4 = new Ipv4PacketParser<EthernetFrameParser<RamPacketData<256>>>(ethernet)
}
```

Publish the initialized source prefix, parse Ethernet, check `GetEtherType()`,
then parse IPv4. Every parser also implements `IPacketData` for its bounded
**payload**, so `TcpHeaderParser<Ipv4PacketParser<...>>` composes in the same way.
ARP consumes the Ethernet payload; it never assumes a frame offset of 14.

## Results and metadata

`TryParse()` discards the previous parse, including on failure. `GetStatus()`
reports the last structural result; `IsReady()` means supported metadata and a
bounded captured payload are available.

| Result | Meaning |
|---|---|
| NotReady | No parse or source unavailable/read failed |
| Truncated | Required header bytes are missing; no validated metadata |
| Invalid | Inconsistent lengths or malformed header fields |
| Unsupported | Unsupported protocol/header format; no validated metadata |
| HeaderOnly | Supported header with incomplete or unknown capture completeness |
| Success | Supported structure with the protocol's required bytes captured |

Ethernet returns HeaderOnly because `IPacketData` has no wire length or FCS
contract. Its captured payload may include Ethernet padding. A frame-link owner
can independently inspect known wire length; parsing does not manufacture it.

IPv4 accepts version 4, IHL 5 and unfragmented packets (flags 0 or DF only).
Total length must cover the header. It excludes trailing padding from the
payload and returns HeaderOnly when the IP total length exceeds the capture.
`GetTotalLength()` and `GetDeclaredPayloadLength()` remain available in that
case; `GetAvailableLength()` reports only captured payload bytes.

TCP validates its minimum header and data-offset extent. It skips captured
options without interpreting them, rejects reserved/extended flag bits, and
bounds payload after the declared TCP header. Standalone TCP Success does not
prove a complete enclosing IP packet. `TcpConnectionRecognizer` composes the
layers, propagates IPv4 HeaderOnly and applies IP/port/flag acceptance separately.
It accepts SYN options; ACK/PSH+ACK policy retains the fixed-header subset.

Metadata getters return decoded lengths, ports, unsigned 32-bit sequence numbers
and small address arrays. On unavailable/failed parses they return zero values;
check status to distinguish these from legitimate zeros. The fixed header
portion is cached once per parse, not reread from packet storage by each getter.
TCP options are bounded and skipped, not decoded or cached.

## Checksums and compatibility of packet behavior

Success is **structural**, not checksum validation. Ethernet FCS, ICMP and TCP
receive checksums remain unchecked, preserving the existing demo's policy.
`Ipv4PacketParser.IsHeaderChecksumValid()` explicitly checks the cached IP header;
it is not an implicit admission gate. ARP has no checksum.

Malformed declared lengths, truncated TCP options and ARP carried under a wrong
EtherType are now rejected rather than accidentally recognized through fixed
array offsets. Tests constructing synthetic packets must provide consistent
lengths and EtherTypes. Valid existing reply bytes remain the regression target.

The Web recognizer deliberately accepts a captured `GET <path> ` prefix of a
supported PSH+ACK packet. That is token recognition, not complete HTTP or TCP
validation. It checks the bounded payload so Ethernet padding cannot supply a
missing token. ICMP reply preparation requires the complete declared IP packet.

## Lifetime and scheduling

The source must stay published/acquired and unchanged while parsers or payload
views depend on it. Finish reads, invalidate descendants before ancestors, then
release/reuse storage. For the graph above: invalidate TCP, IPv4, Ethernet, then
release the source. Parse again after publication of the next packet. Metadata
is a cached snapshot gated by that parse lifetime, not an independently retained
packet handle. There is no generation counter: releasing and republishing a
source behind still-open parsers violates the same ownership contract as doing
so behind PacketRegion. An unavailable source is detected; arbitrary ownership
violations cannot be detected after republication.

Do not call TryParse or Invalidate while a descendant still borrows its payload.
Provider reads and component calls are scheduled, including cache getters.
Header caching avoids repeated provider reads; it does not promise equal latency
to direct array indexing. RAM latency is supplied by the provider. No synthesis,
area, timing or throughput claim is made.

`ArpResponder<S>(ethernet)` and `IcmpEchoResponder<S, CAPACITY>(ethernet, ipv4)`
borrow shared parsers over an Ethernet-frame provider and offer `TryPrepare(localMac, localIp)`. They snapshot the necessary
request data into their reply graph. After any preparation attempt, call
Invalidate before releasing their input if the attempt failed; on success their
input views are already closed. Keep a successful reply stable until emission
finishes. Old array-based parser/responder overloads and ShouldRespond were
removed; recognition-only callers use the parsers and endpoint policy explicitly.

`TcpConnectionRecognizer<S>(ethernet, ipv4)` likewise borrows the shared pair
and owns only its TCP parser. Finish payload reads and invalidate TCP before
another consumer reparses Ethernet/IPv4. `FrameClassification<S>(ethernet, ipv4)`
uses the same pair for diagnostics under this serialized ownership contract.

Services may call `TryPrepareParsed(mac, ip)` on ARP/ICMP responders after admission
has validated the shared views. This skips rereading the enclosing headers but
still validates the protocol request and snapshots response data. `TryPrepare`
remains the entry point when parsing has not been performed. An unsuccessful
preparation must be invalidated before releasing its request source.
