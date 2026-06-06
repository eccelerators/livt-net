# Livt.Net Design Notes

These notes apply the Livt design guide to the current `Livt.Net` package
without changing the critical source implementation.

## Package Boundary

Reusable networking logic belongs in `Livt.Net`:

- protocol parsers
- protocol recognizers
- checksum helpers
- frame builders and composers
- endpoint dispatchers
- hardware-boundary adapters

Application packages should own:

- page content and static data stores
- route policy beyond the small configured route IDs
- board-specific wiring
- LEDs, buttons, and showcase behavior
- deployment-specific MAC, IP, and port choices

`WebServer` remains in `Livt.Net` for the current package because it is a compact
adapter over `NetworkEndpoint` and is covered by existing tests. Applications
still own the response body bytes and body checksum metadata.

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

Some public byte-returning APIs still use `logic[8]` where they feed directly
into existing hardware-oriented paths. Treat those as part of the current
published surface until a planned API cleanup can safely change call sites.

## Current Limits

The current package contract is fixed-size:

- 64-byte Ethernet/ARP helper frames
- 128-byte endpoint/request frames
- 20-byte IPv4 headers
- 20-byte TCP headers
- short configured HTTP paths
- externally supplied HTTP body bytes

Future releases may introduce domain folders, clearer app-package separation,
larger frame buffers, route tables, UDP, and streaming response adapters.
