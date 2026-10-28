# TFTP upload engine

`TftpWriteServer<P, S, TRANSFER_PORT, RETRY_MS, MAX_RETRIES, WRITE_CHUNK_BYTES, STYLE, B>` implements a bounded
RFC 1350 upload engine over an `IPacketData` UDP payload and an `ITftpWriteSink`.
It accepts octet-mode WRQ and 512-byte DATA blocks, with one active transfer.
Options in a well-formed request are ignored and ACK zero selects the baseline
protocol. RRQ and option negotiation are not implemented. Filenames are limited
to 63 bytes. Block rollover is unsupported: the transfer must terminate with a
short block no later than block 65535.

`STYLE` selects the decoder's 516-byte snapshot backing: `MemoryStyle.Block`
(default), `MemoryStyle.Distributed`, or `MemoryStyle.Auto`. The same trailing
parameter is available on `TftpRequest<P, STYLE, B>` when used directly. Storage
selection preserves snapshot lifetime, bounds and scheduled access semantics.
`Auto` lets synthesis infer storage; it does not force a register array. The
current language has no `MemoryStyle.Registers`.

`WRITE_CHUNK_BYTES` defaults to 64 and accepts 1..512. Each wire DATA block is
staged as ordered chunks, with one ACK only after every chunk succeeds. The
final empty DATA block calls `Write(0)` before commit. Sink implementations must
accept chunk boundaries that do not coincide with page, file or packet boundaries.

The composition root creates one `TftpUploadBuffer` and binds the **same instance**
to the server and sink. `ITftpWriteSink.Begin(length)` reads its staged filename;
`Write(length)` reads its staged data. Neither call passes an array by value.
The sink must finish all reads before returning and must not modify the buffer.
For NOR storage, keep this buffer separate from the SPI driver's staging page:
readback overwrites SPI staging, but verification still needs the original bytes.

```livt
upload = new TftpUploadBuffer<MemoryStyle.Block>()
sink = new MySink(upload)
server = new TftpWriteServer<MyDatagram, MySink>(datagram, sink, upload)
```

`TftpUploadBuffer<STYLE, B>` implements `ITftpUploadBuffer` with one owned 576-byte
RAM: bytes 0..63 retain the filename, and bytes 64..575 stage upload data. Its
`SetNameByte`/`GetNameByte` and `SetDataByte`/`GetDataByte` methods use indices
relative to those regions. Invalid writes return false without mutation; invalid
reads return zero. Valid unwritten bytes are unspecified. Stage every byte of a
prefix before passing its length to the sink. Reset abandons protocol state;
it does not promise erased staging contents. The server retains the filename
through the entire session, including the final-ACK grace period, and never
stages a competing WRQ over the active filename.

Shared staging and packet snapshot backing are independently selectable. For
example, `TftpUploadBuffer<MemoryStyle.Auto, ArrayRam<byte, 576>>` selects a
resettable logic array. The default `B` is `Ram<byte, 576, STYLE>` with Block
style; Auto and Distributed are also supported. Custom backends must provide
at least 576 bytes. Scheduled access latency depends on the selected backend.

The network integration owns UDP validation, local address matching, ARP/link
address resolution, listening-port dispatch and Ethernet transmission. Dispatch
port 69 and the configured transfer port (default 1069) to `Receive`; replies
originate from the transfer port. Source IPv4 and UDP port identify the session.
`responseIp` and `responsePort` are valid while a reply is published.

Call `Poll(nowMs)` regularly using a wrapping millisecond timestamp. Send the
published `IPacketData` response, retain it throughout transmission, then call
`Release`. Never mutate or cancel a response while the transmitter borrows it.
`Cancel` aborts an incomplete upload after the network borrow has ended.

The engine acknowledges duplicate blocks without repeating storage writes and
retains the final ACK for a bounded grace period. It acknowledges completion
only after `Commit` succeeds. `ITftpWriteSink` separates protocol behavior from
flash, RAM, filesystems and application-specific validation. A failed write or
commit calls `Abort`. Storage operations are scheduled and may block; integration
must account for their latency in receive buffering and timeout configuration.

This is an upload engine, not a standalone Ethernet endpoint. No authentication
is provided. Applications should enable uploads only on their intended trusted
network or behind an explicit access gate.

```sh
livt test -r TftpWriteServerTest
```

Protocol reference: [RFC 1350](https://www.rfc-editor.org/rfc/rfc1350.html).

The optional storage type `B: IRam<byte> & new()` defaults to
`Ram<byte, 516, STYLE>`. The decoder owns this buffer, which must provide at
least 516 bytes. To use resettable logic-array storage instead of inferred RAM:

```livt
TftpWriteServer<MyDatagram, MySink, 1069, 1000, 5, 64,
    MemoryStyle.Auto, ArrayRam<byte, 516>>
```

An explicit `B` overrides the default implementation; `STYLE` only configures
the default `Ram`. Snapshot lifetime and failed-load invalidation remain the
same for all backends. The sink interface owns no payload memory; staging
selection belongs to the composition root, independently of the sink.

## Migrating an array-based sink

Bind `ITftpUploadBuffer` in the sink constructor. Replace `Begin(name, length)`
with `Begin(length)` and read names through `GetNameByte(index)`. Replace
`Write(data, length)` with `Write(length)` and read data through
`GetDataByte(index)`. Bind that same buffer as the server constructor's third
argument. Preserve transactional commit/abort behavior and complete every
staging read before returning from each call.
