# Bounded TCP stream server

`TcpStreamServer<S, PORT, RX_CAPACITY = 512, TX_CAPACITY = 256, SESSIONS = 1>` provides
a bounded set of passive IPv4 TCP connections over a borrowed Ethernet frame source and shared
Ethernet/IPv4 parsers. It accepts local connection requests and exposes scheduled
`TryReceive`/`TryTransmit` byte operations. The source and parsers share one clock
and reset context. All server operations have one serialized owner.

The default remains one connection. `SESSIONS` accepts 1..16. Each slot owns
independent TCP metadata, retry timing and disjoint regions of the shared RX/TX
RAMs. Parsers, checksum arithmetic and the output frame builder are shared.
Connections are matched by remote IPv4 address and TCP port before a free slot
can accept a SYN. Extra clients are ignored while all slots are occupied.

For `SESSIONS = 1`, the server, send buffer and retry timer select slot zero
through compile-time specialization. Multiple-session selection remains indexed;
existing checked selection rules still apply. This expresses the intended
hardware structure without promising a particular area or timing result.

## Ownership and progress

Call `TryHandle(now)` while an RX frame is acquired; it consumes the frame only
for that call and closes its parser views before returning. Supply monotonic
unsigned milliseconds, using wrapping subtraction for elapsed time. Call
`Poll(now)` even when no frames arrive. It prepares acknowledgments, stream
output, retransmissions and close responses, and reports a published
`IPacketData` Ethernet frame. Keep that publication unchanged until local
transmission completes, then call `ReleaseFrame()`.

For application byte operations, first call `SelectSession(index)` and check its
boolean result. It selects the slot for state/generation queries, `TryReceive`,
`TryTransmit`, `Close` and `Abort`. Invalid indices and a published frame reject
selection without mutation. `TryHandle` selects the matching connection;
`Poll` rotates across slots, emitting at most one frame and advancing its starting
slot after each candidate. Always select again after these calls before using
application byte operations. `GetSession` identifies the selected or published
slot. `AbortAll` discards every slot when no frame is published. A single owner
must serialize all of these operations.

While a frame is published, do not call connection-mutating methods, including
`Abort` and `Close`. Reading the frame does not transfer ownership of the retained
TCP payload. Only peer acknowledgment releases that payload; local MAC completion
alone does not. No method promises a single-cycle completion.

`TryTransmit` accepts a byte into bounded storage, not into the peer application.
Failure requires retry. `TryReceive` removes one ordered byte; failure assigns
zero. `IsConnected`, `GetState`, `HasPendingOutput` and `GetGeneration` expose
snapshots. A new accepted connection increments that slot’s generation so applications
can clear session-specific state. `HasPeerClosed` identifies received FIN;
finish draining input/output, then call `Close` to send FIN. `Abort` discards
local state without a graceful exchange. Coordinated reset also abandons work.

## Storage and protocol bounds

One block-style RAM holds received bytes and one holds outbound bytes until
acknowledged, each partitioned into SESSIONS disjoint regions. Capacities apply per
connection; small connection metadata remains in registers. Transmissions use a view of the retained RAM, including after a
partial acknowledgment; there is no additional retransmission payload copy.
The RX ring advertises available space and discards out-of-order data, requesting
retransmission through cumulative acknowledgments. Accepted duplicates are not
re-delivered. The transmit window is bounded by the peer window and one segment
at a time, conservatively limiting traffic to at most one MSS in flight.

TX capacity is 1..536 bytes; RX capacity is 1..32768 bytes. SYN MSS options are
parsed, and the sender respects the peer's maximum segment size. Window scaling,
SACK and timestamps are not negotiated. IPv4 and TCP checksums are verified
before connection state changes. IPv4 options and fragmentation are unsupported.

The retry timer uses millisecond RTT estimation, excludes retransmitted RTT
samples and doubles the timeout on repeated loss, with a 60-second maximum.
The initial and minimum timeout is one second. After eight unanswered
retransmissions, the next expiry abandons the connection. Acknowledged idle
connections remain open: silence alone does not indicate a dead peer. There is
no automatic idle disconnect or TCP keep-alive probing. A peer that disappears
without FIN or RST can therefore occupy one slot until an explicit
`Abort`, coordinated reset, or a later transmission exhausts its retries.
A zero peer window causes bounded, backed-off window probes. This implementation targets
small control streams, not high-throughput transfers or a general-purpose host
TCP stack. It supports peer-initiated graceful close, not active open or an
application-initiated FIN before the peer closes. When every slot is occupied, the server ignores additional
connection attempts. It has no authentication, encryption or cryptographic ISN
source.

## Telnet codec

`TelnetSession` is a separate bounded NVT codec. Call `Reset` for each connection,
drain `HasOutput`/`PeekOutput`/`ConsumeOutput`, and feed incoming bytes through
`Accept` only when `CanAccept` is true. `TryRead` supplies decoded terminal input;
`TryWrite` accepts output bytes and escapes IAC. Command and negotiation states
persist across arbitrary TCP packet boundaries.

The codec supports suppress-go-ahead. By default it leaves echo to the client.
For an interactive terminal, construct `new TelnetSession(true)` and bind the
application line editor's echo setting to `session.echoEnabled`. Reset offers
WILL ECHO; the field becomes true only after peer acceptance and false on refusal
or reset. The line editor supplies character, CR-LF and backspace echoes; the
codec does not duplicate them. Incoming WILL ECHO is refused to avoid echo loops.
Unsupported options receive explicit refusal; subnegotiation is skipped without allocation.
CR-LF and CR-NUL input normalize to CR. Application output supplies CR-LF line
endings. Telnet urgent-data/SYNCH and terminal-type/window-size extensions are not
implemented. This plaintext terminal is intended for a controlled development
network.

The application must explicitly choose `PORT` (for example, 23 for Telnet).
The stream server itself does not select an application protocol or listening port.
