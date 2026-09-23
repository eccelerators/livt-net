# Packet data and bounded regions

`IPacketData` is scheduled, read-only access to a published byte prefix. It exposes
`IsReady()`, `GetAvailableLength()` and
`TryRead(index: int, value: out byte) PacketDataResult`.
Always check the result before using the output byte. Failure clears the output
to zero for deterministic behavior; that zero is not successful packet data.

`ArrayPacketData<CAPACITY>` and `RamPacketData<CAPACITY>` implement the same
contract. Capacity must be positive and counts bytes. Both own their storage.
Neither API promises combinational access or a fixed number of clock cycles;
the RAM provider uses scheduled Livt.IO `Ram<byte, CAPACITY>` operations.

## Preparing and publishing a source

1. `TryWrite(index, value)` appends the next initialized byte or overwrites an
   already initialized byte. Negative indices, holes and capacity overflow are
   Invalid. `GetWrittenLength()` reports the prepared prefix.
2. `TryPublish()` freezes that prefix. An empty prefix is valid data, but cannot
   be submitted as an Ethernet frame. Before publication `IsReady()` is false and
   available length is zero; after empty publication it is true with length zero.
3. Readers use only indices below `GetAvailableLength()`. Writes, clearing and
   repeated publication are Busy while published.
4. Finish reads and close every dependent region before `TryRelease()`. Release
   clears publication and prefix metadata, permitting new writes. RAM cells may
   retain old contents, but those cells cannot be read as a new packet.

`TryClear()` abandons unpublished preparation. It is Busy on a published source.
Release without publication is Invalid. Failed operations preserve source state.
Operations are serialized by one owner in one clock/reset context. Publication
freezes mutation; it is not a reference-counted acquisition. `TryRelease()` cannot
detect hidden consumers: releasing while a region/response/TX still borrows the
source is a caller contract violation.

## Composing regions

Construct `PacketRegion<S: IPacketData>` with its fixed source component, then
call `TryOpen(offset, length)`. A region borrows its source and has no payload
storage. It can itself be the source of another region. Offsets are relative to
the immediate parent, not to Ethernet or any other protocol.

Opening requires a ready source and `0 <= offset <= available`, with
`0 <= length <= available - offset`. The subtraction check avoids overflowing
`offset + length`. An empty region at the end is valid. Opening an already open
region is Busy and preserves it; other failures leave the region closed.

Close descendants before `TryClose()` on their parent, then release the source.
Closing makes the region unreadable and permits opening it for a later source
publication. A region does not own its source, automatically release it, or track
publication generations. Never retain an open region across source reuse, even
when the new packet has the same length. Reset all participating components
together and stop readers before reusing storage; retained RAM is not valid data.

For example, construction of two interchangeable source graphs is:

```livt
array: ArrayPacketData<128>
ram: RamPacketData<128>
arrayPayload: PacketRegion<ArrayPacketData<128>>
ramPayload: PacketRegion<RamPacketData<128>>

new()
{
	array = new ArrayPacketData<128>()
	ram = new RamPacketData<128>()
	arrayPayload = new PacketRegion<ArrayPacketData<128>>(array)
	ramPayload = new PacketRegion<RamPacketData<128>>(ram)
}
```

After publishing a source, open the appropriate region and pass that region to a
generic consumer constrained by `IPacketData`. Use the checked read result, not
zero-filled reads, to distinguish missing data from actual 0x00 bytes.

## Metadata boundaries

Capacity, readable prefix, protocol-declared length and actual wire length are
different facts. `IPacketData` exposes only the readable prefix. Protocol parsers
must validate their declared lengths independently; device adapters must report
wire-length knowledge separately. Neither fact is inferred from provider capacity.
EtherType, IP protocol and precomputed checksums are not requirements of a byte
source. Future optional capabilities belong in protocol composition rather than
this interface. A checksum-sum capability must define whether its first byte is
the high or low byte of a word and how an odd trailing byte is represented before
sums can be combined.

Prepared Ethernet, IPv4, ICMP and ARP components also implement `IPacketData`.
See [packet composition](packet-composition.md) for construction and preparation.
