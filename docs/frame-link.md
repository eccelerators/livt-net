# Buffered frame links

`IFrameReceiver` and `IFrameTransmitter` are independent capabilities. They expose
frame data, ownership and results without bus signals or register details. One
serialized service owner operates each in a single clock/reset domain. RX and TX
can overlap when storage is independent.

`TestFrameReceiver<CAPACITY>` and
`TestFrameTransmitter<P: IPacketData, MAX_LENGTH = 1514, CANCELLABLE = true>` are
deterministic test implementations. EthernetFrameIo has not yet been migrated to
these capabilities; its driver extraction is a separate change.

## Construction

A transmitter binds its byte source at construction. `TrySubmit()` submits that
source's current prepared publication. A service can expose one IPacketData source
and keep its selected response stable during a submission. No runtime-selected
component reference or dynamic callback is required.

Separate RX and TX construction avoids cycles when a response borrows RX. Create
the receiver, its region/response graph, then the transmitter. For example:

```livt
receiver: TestFrameReceiver<128>
transmitter: TestFrameTransmitter<TestFrameReceiver<128>>

new()
{
	receiver = new TestFrameReceiver<128>()
	transmitter = new TestFrameTransmitter<TestFrameReceiver<128>>(receiver)
}
```

This setup can forward acquired bytes. A forwarding service must establish that
its capture is complete before submitting; a readable prefix alone does not prove
that. The tests include a service constrained only by `IFrameReceiver` and
`IFrameTransmitter`, checking known wire length against the captured prefix.
Alternatively bind a transmitter to a prepared EthernetFrame or response service.

## Receive capability

| Operation | Contract |
|---|---|
| HasReceiveFrame | True for a published or acquired frame |
| TryAcquire | Success once; Busy if already acquired; NotReady if absent/resetting; DeviceFailure for a latched capture error |
| IPacketData reads | Available only while acquired; invalid indices return PacketDataResult.Invalid |
| GetReceiveCapacity | Allocated capture capacity, not packet length |
| HasKnownWireLength / GetWireLength | Explicit known flag plus actual frame length, exposed while acquired; zero is not an unknown sentinel |
| TryRelease | Success after dependent readers/regions finish; Invalid without an acquisition; NotReady during reset |
| HasReceiveError / TryAcknowledgeReceiveError | Latched capture error until acknowledgment or reset; acknowledgment without an error is NotReady |

Bytes start at destination MAC, exclude preamble/FCS and include captured padding.
GetAvailableLength is only the safe captured prefix. Known wire length larger
than that prefix denotes truncation; unknown length stays unknown regardless of
capacity. Empty captures are distinct from no published frame. Protocol-declared
lengths and packet validity remain parser responsibilities.

Close all dependent regions/responses before release. The raw receiver cannot
discover references held elsewhere. Released storage may be overwritten, and
retained array/RAM values cannot be treated as a new packet.

## Transmit capability

Test adapters advertise lengths 60..MAX_LENGTH, excluding preamble/FCS and
including padding supplied by the composer. They neither pad nor parse frames.
Ready IPacketData supplies a readable publication; the caller chooses a complete
frame source. Unpublished preparation is not admissible.

| TrySubmit result | Meaning |
|---|---|
| Accepted | Borrows the source and all dependencies; no delivery result yet |
| Busy | Transfer or unacknowledged result already occupies the transmitter |
| NotReady | Initialization/reset/backpressure prevents admission |
| Invalid | Source unprepared or available length nonpositive |
| Unsupported | Positive length outside GetMinimumFrameLength/GetMaximumFrameLength |
| DeviceFailure | Device failure prevents admission |

Rejected submissions do not borrow, mutate or consume the source or clear an old
completion. Ownership conflicts take precedence over argument checks. Keep the
source and its dependencies stable while IsSourceBorrowed is true; the link does
not add reference counting to IPacketData. The first contract retains the borrow
until a terminal result even if source reads finish earlier.

TryGetCompletion(outcome) returns Success only for a latched terminal result.
Ignore its output otherwise. Results are Delivered (accepted by the device's
transmit mechanism), Cancelled (cancellation reached local quiescence), or
DeviceFailure (local source reads stopped after failure). Delivered does not mean
physical transmission or remote receipt. Cancellation/failure do not guarantee
that an already committed device transmission was withdrawn.

Repeated reads preserve the result. TryAcknowledgeCompletion clears it and enables
another submission, or returns NotReady when none is present. Source release does
not discard its prepared response or release a response's borrowed RX buffer;
those are separate service cleanup actions.

SupportsCancellation advertises support. TryCancel returns Accepted while keeping
the borrow, Unsupported without changing ownership, Busy for a repeated accepted
request, Invalid without a pending transfer, or NotReady during reset. Wait for a
terminal result before reusing storage, not merely cancellation acceptance.

## Test harness controls

These controls are concrete-adapter methods, outside the public capabilities.
There is no background progress: the harness explicitly advances the fixture.

Receiver:

- InjectByte appends/overwrites an unpublished initialized prefix. Holes and
  overflow are Invalid; published/acquired storage is Busy.
- Publish(known, length) publishes the prefix. A known length cannot be smaller
  than the prefix. Use (false, 0) for unknown length, including partial captures.
- FailReceive discards an incomplete capture and latches an error; it is Busy
  when a successful frame is already available/acquired, preserving that frame.

Transmitter:

- Advance reads at most one source byte. A further advance after the last byte
  publishes Delivered; tests can hold and inspect the borrow until then.
- SetReady(false) prevents admission and pauses reads; cancellation and failure
  still terminate on the next advance.
- SetFailure(true) injects a persistent failure, rejecting admission or terminating
  a borrow on the next advance. Clear it before retrying. Failure takes precedence
  if both failure and cancellation are pending.
- GetCapturedLength/TryReadCaptured expose only initialized trace bytes, including
  partial failed/cancelled transfers. Admission clears the prefix; acknowledgment
  leaves it intact for inspection.

Provider reads are scheduled calls and can take multiple cycles. Advance controls
logical progress, not one-cycle throughput. Indefinitely stalled providers/devices
have no unconditional progress guarantee. Controls and consumer operations follow
the same serialized-owner rule.

## Reset barrier

Production capabilities rely on the owning graph's coordinated clock/reset
context. Test adapters also provide BeginReset/CompleteReset to model that barrier.
Beginning reset rejects new work and hides RX data/completion, but holds an active
TX borrow. CompleteReset ends the borrow and clears prefixes/errors/results. TX
then remains NotReady until SetReady(true) models completed initialization.
Abandoned transfers never become Delivered. Stop/reset all readers and borrowed
sources before completing the barrier; resetting only a provider is invalid.

Livt tests verify these explicit barrier transitions, initial state and reuse.
They do not claim mid-cycle physical reset, hardware timing or bus-reset coverage.
The driver must verify hardware-specific reset behavior during its implementation.
No streaming handshake, synthesis or board run is part of this contract.
