# Changelog

All notable changes to this package are documented here.

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
