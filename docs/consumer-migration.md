# Migrating consumers to the development API

The current Livt.Net 1.1.0-dev API intentionally replaces the previous packet and
link APIs. Mutable development versions alone do not identify tested sources.
Use matching local checkouts of Net, Web and WebApp while developing; choose and
publish compatible package versions together before changing consumers to registry
pins. The existing Web/WebApp 0.1.0 labels do not establish registry compatibility.
No package is published by this migration.

## API changes

| Previous usage | Current usage |
|---|---|
| Raw frame array and valid-length arguments to Net parsers | Bind an `IPacketData` provider; call `TryParse` and inspect its result and decoded metadata |
| Capacity parameter on a parser | Capacity on `ArrayPacketData<N>` or `RamPacketData<N>`; parser type selects the provider |
| Responder byte functions taking a request each time | Bind the provider, `TryPrepare`, then bounded `TryRead`; invalidate before reuse |
| Owned checksum/header-builder instances and scalar/FromBytes overloads | Static helpers with explicit network-order metadata arrays |
| `EthernetFrameIo` | `IFrameReceiver` and `IFrameTransmitter`; concrete EthernetLite wiring at the board boundary |
| Application-owned ARP/ICMP dispatch | `NetworkService`, or custom services/policies and `ServiceChain` |
| Repeated TX admission/completion logic | `ResponseTransfer`, or `FrameService` for a complete service/link loop |

No legacy Net wrappers or duplicate encoders are retained. The raw-request TCP SYN-ACK composer is removed. Use a published empty payload
with `TcpSegment` and the IPv4/Ethernet envelopes. Web
`HttpResponseFrameComposer<P>` now borrows published HTTP body data and prepares
the same TCP graph. See [TCP migration](tcp-composition.md).

See [parsing](packet-parsing.md), [static helper signatures](package-structure.md),
[services](network-services.md) and [EthernetLite construction](ethernetlite.md)
for construction examples. [Common packet names](common-packets.md) covers short
ARP/ICMP forms and explicit custom payload composition.

## Ownership and error handling

Publish only initialized bytes. Acquire RX before parsing and use its available
prefix, not storage capacity or an unverified declared wire length. Check parse
and preparation results before reading metadata or response bytes. Invalidate
outer views before children and release their provider only after dependent reads
finish. A partial capture is not a complete packet; receive checksum validation
is not added by this migration.

A successful TX submission borrows its bound publication until terminal completion
is acknowledged. Busy or rejected submissions do not transfer ownership. Preserve
all dependencies during the borrow, including RX when a response references it.
Handle completion errors before releasing/reusing the response. Reset the driver,
link owners, providers and application together. The contracts in
[packet data](packet-data.md) and [frame links](frame-link.md) define exact results.

Web's endpoint copies a bounded capture and uses Net services and parsers. Finish
response reads before `BeginFrame` invalidates the previous response. WebApp copies
the completed response into published RAM and retains it through `ResponseTransfer`.
AXI is confined to the EthernetLite implementation and WebApp's composition root.

## Verification boundary

Run `livt test -f --events` in Net, Web and WebApp with their local dependencies
resolved. Net checks complete expected ARP, ICMP and SYN-ACK frames, checksums,
padding, parser bounds, service outcomes, ownership and driver failures. Web
checks endpoint dispatch and the supported TCP/HTTP flows. WebApp checks a complete
ARP reply through capabilities, TX backpressure and initial board-driver polling.

These tests do not execute the vendor VHDL wrapper, its reset delay, the Arty
block design, PHY, or an end-to-end HTTP exchange through real EthernetLite.
They do not establish timing, resources or board operation. Generated IP and
bitstreams from before the redesign must be rebuilt for a later hardware check.
The supported transport remains a narrow single-connection, fixed-header web
subset; this migration does not introduce a general reusable TCP stack.
