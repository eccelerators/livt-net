# Livt.Net Hardware Notes

## Frame Model

`Livt.Net` uses compile-time-sized frame arrays and byte-indexed helpers. Ethernet parsing and
ARP helpers default to `byte[64]` where the minimum Ethernet frame is enough.
IPv4, ICMP, TCP, and frame-I/O helpers default to `byte[128]` where
the current request/response tests need more payload space.

The package assumes Ethernet II frames and fixed 20-byte IPv4 and TCP headers.
IPv4 and TCP options are not part of the current hardware contract.

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

`Livt.Net 1.1.0-dev` uses `Livt.IO 1.2.0-dev` generic scheduled RAM.
The portable storage is generated from Livt; `InternalRam` and its handwritten
VHDL are no longer part of the dependency.

## Storage, validity and reset

Defaults retain two 2048-byte stores and a 128-byte RX capture. RX storage can
be explicitly reduced to the capture size; this is a configuration choice,
not a claim about resulting FPGA resource use. Auto supplies no placement hint.

All declared TX payload bytes must be initialized before submission. Reopening
or consuming a buffer invalidates its initialized prefix without clearing RAM.
Unavailable RX reads and invalid/unwritten TX reads return zero. Reset cancels
scheduled work, clears frame metadata and restarts MAC programming. Committed
RAM cells remain stored. The EthernetLite slave must share reset; resetting only
the master during an AXI transaction is not a supported recovery protocol.

`EthernetFrameIo` captures a fixed RX prefix, not an authoritative wire length.
Its AXI interface does not report the actual received length. Applications must
validate protocol lengths and provide a trustworthy valid prefix length to
classifiers when available. A larger array does not make truncated packets valid.

## Transmit bounds and padding

The length register is at byte offset `0x7F4` (2036), before the control register
at `0x7FC`. Payload writes must stay below `0x7F4`; the former 511-word cap could
write into the register area. The checked API now accepts lengths from 1 through
`min(TX_STORAGE_CAPACITY, 2036)` and rejects all others.

Byte zero occupies bits 7..0 of an AXI word. The last word's unused high lanes
are zeroed without reading unwritten RAM. Applications still supply any required
Ethernet minimum-frame padding; bus-word padding is a separate operation.

## Verification and performance

See [the native AXI verification](../verification/ethernet/README.md) for edge
checks, measured transfer timings and any release blockers. Scheduled calls,
RAM arbitration and device stalls all contribute to latency. No area, Fmax or
board-readiness claim follows from passing Livt simulations alone.
