# Livt.Net Hardware Notes

## Frame model

Packet-facing APIs consume bounded `IPacketData` components. Fixed headers are
cached; payloads remain borrowed provider views. Arrays/RAM are storage details,
not parser arguments. See [packet parsing](packet-parsing.md) for supported
headers, structural status and explicit checksum coverage.

## Protocol Scope

The current stack targets:

- ARP requests for the configured local IPv4 address.
- IPv4 packets with fixed headers and no fragmentation.
- ICMP echo requests.
- Complete IPv4 UDP datagrams with optional transmit checksums and validated reception.
- TCP SYN, ACK, PSH+ACK, and FIN+ACK classification for a local port.
- Ethernet-minimum response padding where needed.

Unsupported packet forms are ignored by the endpoint dispatcher.

## Checksums

Checksum helpers follow the RFC 1071 one's-complement checksum model. Several
response builders rely on precomputed word sums where fixed protocol headers
need checksums and caller-supplied body checksum metadata.

Higher-layer response generators own payload bytes and supply:

- body length
- unfolded body word sum

This keeps `Livt.Net` reusable and avoids embedding application content in the
networking package.

UDP uses the Internet checksum for the IPv4 pseudo-header, UDP header and payload.
This is separate from Ethernet CRC32/FCS. `EthernetLiteReceiveWindow` reuses
`Livt.IO.EthernetCrc.Update` for its FCS scan; no CRC32 calculation replaces a UDP
checksum. See [UDP checksum choices](udp.md#checksum-and-scheduling).

ICMP reply preparation splits IPv4 checksum arithmetic across explicit state
boundaries. The reply becomes readable only when preparation completes; callers
must not assume a fixed preparation latency from an earlier release.

## EthernetLite boundary

The device implementation lives in `Livt.Net.Drivers.EthernetLite`. Its receiver
owns capture RAM, transmitter owns source borrowing, and driver owns MAC
programming, RX/TX polling and AXI word transactions. Applications depend on
frame capabilities. See [the driver contract](ethernetlite.md) for construction,
FCS-free bounded captures, TX limits, completion, errors and coordinated reset.

`Livt.Net 1.4.0` uses `Livt.IO 1.5.0` generic scheduled RAM. Storage cells
may retain bytes across metadata reset, but unpublished data is not readable.
There is no equal-latency, FPGA area or timing claim from these abstractions.

## Livt.IO MAC boundary

`Livt.Net.Drivers.Ethernet` adapts IO's complete-frame RX and buffered TX capabilities
without duplicating MAC, PHY or protocol logic. RX reports exact FCS-free length;
TX retains prepared responses through IO wire completion. See the
[adapter contract](ethernet.md). The historical native RMII integration fixture
is not included in this checkout.
Clock-domain crossing and media-rate support belong to the underlying Livt.IO
capability and its composition; the Net adapter adds neither.
The included [MII integration tests](mii.md) cover full frames at 10 and 100 Mb/s
in simulation. These results do not establish FPGA resource use or board timing.

## IPv4 reply header storage

`Ipv4Packet` stores seven 16-bit words (total length, identification, checksum
and the two halves of each address) plus the protocol byte. `TryRead` selects
header bytes from these fields and fixed constants. Preparation uses the existing
`Ipv4HeaderChecksum.Calculate` helper to sum header words directly; it no longer
constructs and rereads a writable 20-byte header array.

Public preparation/read APIs, snapshot ownership, invalid-input behavior and
payload delegation are unchanged. Length and protocol inputs are checked before
narrowing, and the stored length is widened unsigned when exposed as an `int`,
including the maximum total length of 65,535 bytes. Preparation still publishes
readiness only after all fields are captured. Scheduled cycle counts may change.

The [resource architecture](resource-optimization.md) documents the package-wide
storage, arithmetic, scheduling, and verification rules.
