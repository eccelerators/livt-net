# Generic packet composition draft

Status: the isolated compiler acceptance gate passes after the constructor-wiring
fix. These sources remain an implementation draft, not an exported Livt.Net API.
The regular package and its existing WebApp consumers do not include this project.

## Intended usage

Declare and construct one application-owned graph in the same clock context:

```livt
echo: IcmpEchoReply<32>
ip: Ipv4Packet<IcmpEchoReply<32>>
frame: EthernetFrame<Ipv4Packet<IcmpEchoReply<32>>>

new()
{
    echo = new IcmpEchoReply<32>()
    ip = new Ipv4Packet<IcmpEchoReply<32>>(echo)
    frame = new EthernetFrame<Ipv4Packet<IcmpEchoReply<32>>>(ip)
}
```

Once the caller has validated a request, prepare the leaf with its identifier,
sequence and echo data, prepare IPv4 with local/peer addresses and identification,
then prepare Ethernet with local/peer MAC addresses. Check each `TryPrepare`
result before continuing. Emit `frame.GetLength()` bytes using `frame.GetByte(i)`.
An ARP reply uses the same envelope: `EthernetFrame<ArpReply>`.

`IPacketBytes` exposes prepared length and indexed bytes. `IIpv4Payload` provides
the protocol number, and `IEthernetPayload` provides EtherType. Generic constraints
require both the byte-provider and appropriate protocol capabilities. The custom
payload test demonstrates extension without modifying either envelope.

## Contracts

- All address/identifier/sequence arrays use network byte order. Protocol metadata
  comes from the child component, avoiding separately configured protocol numbers.
- ICMP computes its full reply checksum during preparation and copies only valid
  data into its leaf storage. IPv4 computes its header checksum during preparation.
  Parent layers retain small headers and delegate payload reads, rather than
  allocating a full frame at every level.
- IPv4 uses a fixed 20-byte header, DF and TTL 64. Ethernet adds zero padding to
  60 bytes excluding FCS; that padding is outside IP length and checksums. The MAC
  supplies preamble/FCS. Ethernet's default payload limit is 1500, configurable at
  compile time; transport limits still apply independently.
- Unprepared layers return length zero and zero for byte reads. Invalid indexes
  return zero. Failed preparation invalidates that layer's previous result.
- Preparation and emission are serialized. Before changing a child, invalidate
  enclosing layers; then prepare from the leaf outward. A prepared parent borrows
  the child: it does not snapshot its bytes or automatically detect child changes.
  Do not mutate a child during emission, including same-length replacements.
- Initialization/reset leaves readiness false. Payload bytes need not be cleared;
  only the prepared prefix may be read. Invalidate each enclosing layer when
  abandoning a graph. Invalidate is not a substitute for synchronizing reset
  across clock domains; this draft only supports a single-context owner.
- Existing stateless responders and composers remain available. This project
  does not migrate WebApp, implement TCP/UDP, or introduce streaming interfaces.

## Livt verification

Run from this directory:

```sh
LIVT_GHDL_PATH=/home/vagrant/ghdl/bin/ghdl livt test -f -v
```

The original blocker was constructor wiring to private descendant fields such as
`clk` and `sum`, absent from the generated payload input records. The reduced
regression lives in
`livt-gen-vhdl-verification/tests/GenericTests/testNestedBorrowedComponentConstructors`.
A narrow interface-field alternative also failed during generation; it was not
adopted. No generated HDL patches or synthesis workarounds are used.

The tests contain independent full ICMP reply vectors for 32, 3, 4 and
zero echo-data bytes at capacities 32, 96 and 128; ARP full-frame/reuse tests; and
custom-payload metadata bounds. They also check pre-prepare reads, padding,
invalid input lengths and long-to-short reuse. On 2026-09-22, all five tests pass
with the corrected generator and unchanged assertions. Generic packet checks
finish at 405025 ns; metadata checks finish at 22475 ns. The log is
`/tmp/livt510-packets.log`. This is behavioral verification, not synthesis or
timing-closure evidence.

Only `GenericPacketTest` and `PacketMetadataTest` are testbenches. Their helpers
`NestedPacketChecks` and `PacketMetadataStub` are ordinary components sharing the
owner's context. Their previous `@Test` annotations created independent test
clocks that stopped before helper calls could execute; this caused false early
passes and a metadata-test hang. Removing those two annotations changes no
assertions. The rejected run is retained in `/tmp/livt510-packets-invalid-helper.log`.

Promotion remains a separate library task: move the sources/tests into the main
package, document its public API, and run Net, Web and WebApp suites before
declaring NET-010 complete. Passing this isolated compiler gate does not itself
publish or migrate the library API.
