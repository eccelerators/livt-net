# Livt.Net Hardware Notes

## Frame Model

`Livt.Net` uses fixed-size frame arrays and byte-indexed helpers. Ethernet and
ARP helpers operate on `byte[64]` where the minimum Ethernet frame is enough.
IPv4, ICMP, TCP, HTTP, endpoint, and web-server helpers use `byte[128]` where
the current request/response tests need more payload space.

The package assumes Ethernet II frames and fixed 20-byte IPv4 and TCP headers.
IPv4 and TCP options are not part of the current hardware contract.

## Protocol Scope

The current stack targets:

- ARP requests for the configured local IPv4 address.
- IPv4 packets with fixed headers and no fragmentation.
- ICMP echo requests.
- TCP SYN, ACK, PSH+ACK, and FIN+ACK classification for a local port.
- HTTP/1.0 `GET` recognition for configured short routes.
- Ethernet-minimum response padding where needed.

Unsupported packet forms are ignored by the endpoint dispatcher.

## Checksums

Checksum helpers follow the RFC 1071 one's-complement checksum model. Several
response builders rely on precomputed word sums for fixed HTTP response pieces
and caller-supplied body checksum metadata.

For HTTP responses, application code owns the body bytes and supplies:

- body length
- unfolded body word sum

This keeps `Livt.Net` reusable and avoids embedding application content in the
networking package.

## EthernetLite Boundary

`EthernetFrameIo` bridges frame-oriented Livt code to an AXI4-Lite
EthernetLite-style register interface. The adapter targets the Xilinx/AMD AXI
EthernetLite register shape used by the current tests:

- 13-bit AXI4-Lite address bus
- 32-bit AXI4-Lite data bus
- ping/pong receive status polling
- transmit-buffer writes through word packing
- local MAC programming through the EthernetLite control path

The AXI getters on `EthernetFrameIo` are diagnostics-oriented visibility helpers
for simulation and integration tests. Treat them as part of the current
low-level boundary, not as the preferred application API.

## Dependency

`Livt.Net` depends on `Livt.IO` for RAM-backed frame storage in
`EthernetFrameIo`. The nested VHDL source for `Livt.IO.InternalRam` is supplied
by `Livt.IO`; consumers of `Livt.Net` do not need to copy VHDL files manually.
