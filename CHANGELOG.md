# Changelog

All notable changes to this package are documented here.

## 1.4.0

### Added

- `TftpWriteServer`: a bounded RFC 1350 octet-mode upload engine with one active
  transfer, duplicate-block handling, response retries and final-ACK retention.
- `ITftpWriteSink`: a transactional storage boundary with begin, chunked write,
  commit and abort operations, independent of Ethernet and physical storage.
- `ITftpUploadBuffer` and `TftpUploadBuffer`: shared filename and DATA staging
  with selectable inferred RAM or consumer-provided `IRam<byte>` storage.
- `TftpRequest`: bounded WRQ/DATA decoding with an owned packet snapshot and
  configurable storage backend.
- Compile-time RX and TX storage providers for `TcpStreamServer` and
  `TcpSendBuffer`, retaining block RAM as the default.
- Regression coverage for TFTP request parsing, upload transactions, retries,
  duplicate blocks and failure paths, plus TCP storage combinations using block,
  distributed, automatic and array-backed memory.

### Changed

- `RamPacketData` now accepts a `MemoryStyle` parameter for portable inferred,
  block or distributed RAM preference while retaining its existing behavior.
- TCP receive and transmit storage may be selected independently without a
  runtime selector or a change to stream ownership and retransmission semantics.
- Large TCP tests share reusable storage checks while preserving single-session
  and multi-session behavior coverage.

### Compatibility and dependencies

- Existing type arguments remain valid because all new storage parameters are
  trailing and default to block RAM.
- Require `Livt.IO 1.5.0` for `ArrayRam`, configurable RAM implementations and
  the SPI-flash building blocks used by downstream TFTP storage sinks.
- TFTP is an upload engine over a validated UDP payload, not a complete Ethernet
  endpoint. Applications remain responsible for UDP dispatch, address matching,
  response transmission, access policy and transactional storage recovery.
- TFTP supports one baseline octet-mode upload, 512-byte DATA blocks and files
  that terminate by block 65535. RRQ, negotiated options, authentication and
  block rollover are not supported.

### Validation

- TFTP and TCP storage tests cover protocol success and failure paths, storage
  backend combinations and behavior across supported clock contexts.
- Hardware resource mapping, timing and live-network qualification remain the
  responsibility of the consuming design.

## 1.3.1

### Added

- Direct-MII integration documentation for the existing IO-MAC frame adapters.
- Livt integration verification covering full Ethernet framing/FCS, exact packet
  bytes, and frame ownership release using the Livt.IO 1.4.0 MII implementation at 10 and 100 Mb/s.

### Changed

- Keep MII fixtures and helpers as ordinary files under `tests/`, registered in
  the package test catalog; remove development-only verification projects.

- Require `Livt.IO 1.4.0`; publish that dependency before this release.
- Update Ethernet documentation and dependency examples for MII integration.
- Keep existing public frame/protocol APIs unchanged. MII serialization, clock
  crossing, and PHY management remain in Livt.IO.

### Validation

- Both focused MII integration tests pass in Livt simulation. This release does
  not claim a new full-suite pass, FPGA timing result, or hardware qualification.

## 1.3.0

### Added

- Add `UdpHeader`, `UdpEthernetPacket<P>`, `UdpChecksum` and `UdpPacketParser<S>`
  for IPv4 UDP header encoding, borrowed Ethernet frame composition, optional
  checksum generation and complete packet validation.
- Reuse InternetChecksum for UDP payload/pseudo-header validation, including
  odd lengths, omitted checksums and computed-zero encoding.

### Changed

- Specialize single-session TCP selection while retaining multi-session behavior.
- Stage ICMP IPv4 checksum preparation across explicit state boundaries.
- Reuse Livt.IO EthernetCrc.Update in EthernetLiteReceiveWindow.

### Compatibility and scope

- Keep existing public networking APIs and the `Livt.IO 1.2.0` dependency.
- UDP transmission supports payloads up to 1472 bytes, source ports 0..65535,
  destination ports 1..65535 and fixed IPv4 headers with DF and TTL 64.
  `Prepare` omits the UDP checksum; `PrepareChecksummed` includes it.
- UDP reception requires a complete fixed-header IPv4 packet and matching UDP/IP
  payload lengths. A zero UDP checksum is accepted as omitted; nonzero checksums
  are verified. IPv6, fragments, port dispatch and MAC resolution are not added.
- ICMP preparation has additional scheduling boundaries. Preserve the existing
  completion/ownership contract rather than assuming the former cycle count.
- Video packet formats, stream scheduling and media arbitration remain in the
  application. No FPGA area or timing improvement is claimed without synthesis.

### Validation

- Pass 18 directly relevant package cases, six demo packet/streaming cases and
  full board GHDL elaboration/reset after the refactor.
- Full suite: 117 passed, 4 failed, 6 skipped. Three assertions reproduce on the
  committed baseline; the interrupted reset case also times out on that baseline.
  These remain unresolved. See [validation evidence](docs/design-notes.md#ipv4-udp-and-networking-refactor-validation-2026-10-22).

## 1.2.0

### Added

- Add `TcpStreamServer` for bounded passive IPv4 TCP connections with checksum
  validation, receive-window flow control and retained-payload retransmission.
- Support 1–16 configurable connection slots, defaulting to one, with shared
  protocol processing, fair polling and independent connection state.
- Partition shared receive/transmit RAMs into per-connection regions; retain
  unacknowledged bytes without a separate retransmission payload copy.
- Add `TcpSendBuffer` and `TcpRetryTimer` with per-session storage and timing,
  RTT-based retry intervals and exponential backoff.
- Handle peer MSS negotiation, partial acknowledgments, duplicate suppression,
  sequence wrap, zero-window probes and peer-initiated graceful close.
- Add `TelnetSession` with bounded negotiation, optional server echo,
  suppress-go-ahead, IAC escaping and CR-LF/CR-NUL input normalization.
- Add regression coverage for stream lifecycle, idle connection retention,
  retries, multiple-session isolation, capacity limits, slot reuse and Telnet.
- Document stream ownership, publication lifetime, RAM layout and protocol limits.

### Compatibility and scope

- Keep existing packet parsing, composition and service APIs unchanged.
- Continue to depend on `Livt.IO 1.2.0`.
- Target small control streams with one outstanding segment per connection.
  Active open, application-initiated graceful close, TCP keep-alive, window
  scaling, SACK and timestamps are not supported. Telnet provides no
  authentication or encryption.
