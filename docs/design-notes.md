# Livt.Net Design Notes

These notes apply the Livt design guide to the current `Livt.Net` package
with compile-time capacities and explicit buffer ownership.

## Package Boundary

Reusable networking logic belongs in `Livt.Net`:

- protocol parsers
- protocol recognizers
- checksum helpers
- frame builders and composers
- endpoint dispatchers
- hardware-boundary adapters

Application packages should own:

- application payload content and data stores
- application protocol policy
- platform-specific wiring
- LEDs, buttons, and showcase behavior
- deployment-specific MAC, IP, and port choices

Web-server components live in `Livt.Web`; `Livt.Net` keeps only reusable packet and frame-I/O primitives.

Applications also own response body bytes and body checksum metadata.

## Naming and Namespaces

The public package uses the shallow `Livt.Net` namespace. That follows the
design-guide preference for readable, short namespaces around a single logical
purpose.

Tests use `Livt.Net.Tests` so package tests mirror the public library namespace.

## Component Shape

The package follows four repeated component roles:

- parsers read fixed frame/header bytes and expose `Is...` and `Get...` helpers
- recognizers combine protocol checks for a specific packet type
- builders return one response-header byte for a supplied index
- responders/composers select a response and return one frame byte at a time

This shape keeps responsibilities small and makes byte offsets visible.

## Types

Frame payload values use `byte` where possible. Hardware buses and AXI signals
use `logic` or `logic[N]`. Boolean classifiers return `bool`.

Hardware-facing byte APIs may use `logic[8]` when they connect directly to logic
vectors. Packet and protocol APIs use `byte`; convert explicitly at the boundary.

## Current Limits

The default package configuration uses:

- 64-byte Ethernet/ARP helper frames
- 128-byte endpoint/request frames
- 20-byte IPv4 headers
- 20-byte TCP headers
## Compile-time specialization

Frame consumers use defaulted integer value parameters; child parsers and
builders receive the same capacity. Static assertions enforce the minimum required
header capacity. Classifier length defaults use the
receiver's `FRAME_CAPACITY`; explicit lengths retain their bounds checks.
Network payload types remain `byte`;
only hardware boundaries use logic vectors. No runtime size selection is added.

Frame I/O owns concrete Auto-style `Ram<byte, RX_STORAGE_CAPACITY>` and
`Ram<byte, TX_STORAGE_CAPACITY>` instances. Scheduled memory
access remains the application contract. Configuration does not imply one-cycle
methods, physical RAM mapping, or portable timing. ICMP snapshot storage is a
constructible generic with a RAM default; streaming remains a separate API shape
for consumers that require sustained throughput.

Use a single application process that serializes frame lifecycle calls. Checked TX methods
accept contiguous writes and overwrites within the initialized prefix; they
reject holes, writes after submission and attempts to replace an in-flight frame.
`ConsumeTxFrame()` cannot cancel device-owned work.
