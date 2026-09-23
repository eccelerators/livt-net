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
- TCP SYN, ACK, PSH+ACK, and FIN+ACK classification for a local port.

- Ethernet-minimum response padding where needed.

Unsupported packet forms are ignored by the endpoint dispatcher.

## Checksums

Checksum helpers follow the RFC 1071 one's-complement checksum model. Several
response builders rely on precomputed word sums where fixed protocol headers need checksums
and caller-supplied body checksum metadata.

Higher-layer response generators own payload bytes and supply:

- body length
- unfolded body word sum

This keeps `Livt.Net` reusable and avoids embedding application content in the
networking package.

## EthernetLite boundary

The device implementation lives in `Livt.Net.Drivers.EthernetLite`. Its receiver
owns capture RAM, transmitter owns source borrowing, and driver owns MAC
programming, RX/TX polling and AXI word transactions. Applications depend on
frame capabilities. See [the driver contract](ethernetlite.md) for construction,
FCS-free bounded captures, TX limits, completion, errors and coordinated reset.

`Livt.Net 1.1.0-dev` uses `Livt.IO 1.2.0-dev` generic scheduled RAM. Storage cells
may retain bytes across metadata reset, but unpublished data is not readable.
There is no equal-latency, FPGA area or timing claim from these abstractions.

Current verification uses Livt tests only. Historical native AXI and board
results for EthernetFrameIo do not verify the extracted implementation.
