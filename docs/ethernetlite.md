# EthernetLite frame-link implementation

The concrete device types live in `Livt.Net.Drivers.EthernetLite`. Protocol code
uses `IFrameReceiver`, `IFrameTransmitter` and `IPacketData` from `Livt.Net`.
`EthernetFrameIo` and its raw byte injection/TX staging API have been removed.

## Construction and ownership

Construct RX first, then any response graph, then TX and the driver. For example:

```livt
using Livt.Net
using Livt.Net.Drivers.EthernetLite

component EthernetPort
{
	receiver: EthernetLiteReceiver<128>
	response: RamPacketData<1514>
	transmitter: EthernetLiteTransmitter<RamPacketData<1514>>
	bus: EthernetLiteBus
	driver: EthernetLiteDriver<EthernetLiteBus, RamPacketData<1514>>

	new(axi: IAxi4LiteEthernetLiteMaster, mac: byte[6])
	{
		receiver = new EthernetLiteReceiver<128>()
		response = new RamPacketData<1514>()
		transmitter = new EthernetLiteTransmitter<RamPacketData<1514>>(response)
		bus = new EthernetLiteBus(axi)
		driver = new EthernetLiteDriver<EthernetLiteBus, RamPacketData<1514>>(
			bus, receiver, transmitter, mac)
	}
}
```

`EthernetLiteReceiver<CAPACITY = 128>` owns RAM and acquisition metadata.
`EthernetLiteTransmitter<S, MAX_LENGTH = 1514>` owns admission/borrow/completion
metadata and borrows the prepared source. It does not allocate another TX copy.
`EthernetLiteDriver<B: IEthernetLiteRegisterAccess, S, RX_CAPACITY = 128,
MAX_TX_LENGTH = 1514>` owns register sequencing and borrows word access plus both
frame capabilities. `EthernetLiteBus` adapts the board signal interface to the
shared `EthernetLiteTransactions` core. Its live pins are wired in context-free
processes; the Livt fixture drives those same pins with independent channel stalls.
Storage sizes and source types must agree at construction.

Only the driver may call the concrete capture/pending-read/completion methods.
The application uses the public frame capabilities, owns prepared source mutation
and closes all dependent RX views before release. No reference counting or
concurrent multi-owner lifecycle is provided. RX can remain acquired during TX.

## Receive prefix

EthernetLite reports receive completion after CRC checking, but has no independent
actual-length register for arbitrary Ethernet II frames. Its memory includes FCS.
Reading a fixed capacity unconditionally could publish FCS or retained tail bytes
from a previous packet. IP/802.3 length fields are not trusted as wire length.

The driver scans at most `RX_CAPACITY + 4` octets, stopping at the first Ethernet
CRC residue after at least 64 octets. It publishes at most the bytes preceding
that candidate FCS. If no residue appears in the lookahead window, the first
`RX_CAPACITY` bytes precede the real FCS of the CRC-accepted packet. A coincidental
earlier residue can only shorten the capture, so **wire length remains unknown**.
This establishes a conservative prefix, not an authoritative frame boundary.

The argument relies on the device's CRC-accepted receive status and minimum-frame
filtering. It is not a generic parser for arbitrary memory or a replacement for
receive checksums at higher layers. The driver reads little-endian words in wire
byte order, handles FCS in every word lane and never publishes FCS/lookahead data.

Capture capacity is 60..1514 bytes and need not be word aligned. The prefix is
published only after the RX-bank release write succeeds. Partial capture errors
publish nothing. Error acknowledgment does not itself repair the device.

Hardware assumptions: [AMD receive interface](https://docs.amd.com/r/en-US/pg135-axi-ethernetlite/Receive-Interface)
and [retained FCS](https://docs.amd.com/r/en-US/pg135-axi-ethernetlite/FCS).

## Transmit and errors

TX admission is NotReady until MAC programming finishes. The driver waits for
both MAC-programming command bits to clear before enabling admission. Pending TX
waits for the device's idle status before writing any data.

Frames must contain 60..MAX_LENGTH initialized bytes, including Ethernet padding,
with MAX_LENGTH at most 1514. Oversized nonstandard frames formerly admitted by
the raw buffer API are rejected. Final unused AXI word lanes are zero without
reading beyond the source publication. Register writes stay outside the data.

The source stays borrowed until a latched terminal result. Delivered means the
TX start-command write received AXI OKAY; it does not mean physical transmission,
remote receipt or acknowledgment. Results remain readable until acknowledged.
Cancellation is unsupported and never releases a pending borrow.

Source-read failure terminates TX with DeviceFailure and no start command. AXI
read/write error responses stop the driver, terminate pending TX with DeviceFailure
and latch RX error without revoking an acquired frame. RX error and TX admission
failure are published before HasDeviceError becomes true; TX error completion
is published after that flag. Initialization is reported only after TX admission
is enabled. A failed start write may
have affected the device; retry is not a promise of exactly-once delivery.

The boundary owner can acknowledge errors/results and call `TryRecover()` after
a completed error response. Recovery reprograms the MAC after the TX busy/program
bits clear. An indefinitely stalled AXI transaction has no timeout or local abort.

## Reset and verification limits

Driver, capabilities, borrowed source/readers and the external MAC must share a
coordinated reset. Reset clears metadata, disables admission and restarts MAC
programming; RAM contents are not considered valid merely because they remain.
Resetting only one participant during an outstanding transaction is unsupported.

Verification uses Livt tests with a device register model, independent channel
stalls, error responses, CRC vectors, retained storage and capability-only
application tests. Simulation does not establish resource use, timing or board
readiness. Historical native harness evidence applies to the former driver,
not this implementation. No synthesis or native harness is required here.
