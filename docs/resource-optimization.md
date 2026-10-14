# Resource architecture

Livt.Net treats resource use, latency, throughput, and error handling as part of
each component contract. Compile-time configuration removes runtime selectors;
scheduled application APIs bound work and make backpressure explicit. Consumers
must still synthesize representative compositions for their device, clock, reset
policy, and traffic requirements.

## Storage

Fixed Ethernet, ARP, IPv4, ICMP, and TCP fields use compact scalar registers and
pure byte selectors. Constants are emitted directly. Variable packet bodies use
an `IPacketData` provider and are not copied unless a response must outlive its
request.

`IcmpEchoResponder<S, FRAME_CAPACITY, B>` owns a constructible writable backend.
The default `B` is `RamPacketData<FRAME_CAPACITY>`; callers can select
`ArrayPacketData<FRAME_CAPACITY>` or another compatible
`IWritablePacketData<PacketDataGeometry<FRAME_CAPACITY>>`. The geometry type
makes capacity compatibility a compile-time requirement. Backend selection adds
no runtime tag, dispatch path, forwarding component, or duplicated storage.

Use array storage for small values when direct register storage is appropriate.
Use RAM storage for larger retained packet bodies when the selected synthesis
flow infers the intended memory. RAM operations are scheduled and may take more
cycles than array access. Release and reset clear ownership metadata without
erasing cells, preserving memory inference and avoiding unnecessary reset logic.

## Arithmetic and bounded work

Packet parsing and checksum code contains no runtime division or modulo.
Protocol fields whose divisors are powers of two use unsigned shifts and masks,
which preserve the documented non-negative ranges. Checksum folding masks the
low 16 bits and shifts the unsigned high half. Compile-time size calculations
remain constant expressions.

Header capture loops have static bounds. Payload preparation and transmission
advance through scheduled provider calls and perform bounded work per step.
Checksum preparation streams each payload once and combines its word sum with a
balanced fixed-header reduction. The APIs do not promise one byte per cycle;
consumers that require sustained line rate need a streaming composition sized
and measured for that throughput.

## Ownership and timing

Parsers borrow their source and keep only fixed metadata. Descendants must close
before ancestors, and all readers must finish before source release or reuse.
Prepared responders own the metadata and body snapshots required after request
release. Frame transmitters retain their source borrow until a terminal result
or coordinated reset completes.

Scheduled methods provide application-level admission, completion, and checked
results. Device adapters keep cycle-sensitive MAC, RMII, and AXI behavior at
their hardware boundaries. A scheduled call does not imply fixed latency.
Components document serialization, backpressure, cancellation, reset, and
result-lifetime requirements in their public interfaces.

## Verification expectations

Behavioral tests cover supported capacities, boundary lengths, malformed and
truncated input, read failures, publication and release, backpressure, reset,
and reuse. Storage tests exercise RAM and array implementations through the same
contract, including the default and explicit ICMP backend specializations.

For a hardware-cost change, compare equivalent complete compositions and keep
the source version, compiler and generator versions, synthesis target,
constraints, reset policy, optimization settings, resource report, and timing
estimate with the engineering evidence. Synthesis estimates do not establish
routed timing or system throughput, and simulation does not establish resource
efficiency.
