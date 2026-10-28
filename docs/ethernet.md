# Livt.IO Ethernet frame adapters

`Livt.Net.Drivers.Ethernet.EthernetFrameReceiver` and
`EthernetFrameTransmitter<S: IPacketData>` adapt Livt.IO's buffered MAC to
`IFrameReceiver` and `IFrameTransmitter`. They contain no PHY configuration,
RMII/MII pin handling or protocol implementations. Existing `NetworkService` and
`FrameService` supply ARP/ICMP handling and response lifetime management.

See [MII integration](mii.md) for Livt.IO 1.5.0 wiring and the included 10/100 Mb/s
package tests. The same frame ownership contract applies to both media.

## Construction and ownership

Create the IO receiver and transmitter over the same media/link graph, then:

```livt
receiver = new EthernetFrameReceiver(rxMac)
ethernet = new EthernetFrameParser<EthernetFrameReceiver>(receiver)
ipv4 = new Ipv4PacketParser<EthernetFrameParser<EthernetFrameReceiver>>(ethernet)
service = new NetworkService<EthernetFrameReceiver>(receiver, ethernet, ipv4, localMac, localIp)
transmitter = new EthernetFrameTransmitter<NetworkService<EthernetFrameReceiver>>(txMac, service)
endpoint = new FrameService<EthernetFrameReceiver, NetworkService<EthernetFrameReceiver>, EthernetFrameTransmitter<NetworkService<EthernetFrameReceiver>>>(receiver, service, transmitter)
```

The package MII tests exercise the real IO MACs and frame adapters. A hardware
composition supplies PHY management and reset sequencing as documented in
Livt.IO. IO remains independent of Net.

Each adapter exclusively owns its underlying IO capability. Do not call that
capability from another owner. RX and TX have independent storage and may overlap;
each Net capability has one serialized application owner. All MACs, adapters,
readers and response sources share the same 50 MHz clock and coordinated reset.
The test composition passes MAC/IP addresses as stable constructor parameters.

## Receive behavior

The receiver delegates reads directly to IO's acquired storage. It does not copy
frames into a second RAM. Successful acquisition caches the exact frame length;
`GetAvailableLength` and `GetWireLength` expose that length only while acquired.
`HasKnownWireLength` is true only during acquisition. Bytes start at destination
MAC, retain padding, and exclude preamble/SFD/FCS. IO never publishes a partial or
bad-FCS frame. IO's discard counters remain diagnostics on the IO receiver; wire
discards do not become a Net storage failure.

Unacquired reads return `NotReady`; negative and out-of-range indices return
`Invalid`. Local IO read failure also returns `Invalid` and remains visible
through the IO receiver's sticky error capability. Failed reads clear their output
to zero. Reacquiring returns `Busy`;
release without ownership returns `Invalid`. IO receive-error reporting and
acknowledgment are forwarded. Close all regions/responses that still borrow RX
before release. `NetworkService` snapshots its ARP/ICMP request, so `FrameService`
can release RX after preparation while the response remains held for TX.

## Transmit behavior

The minimum submission is 60 bytes; the maximum is the underlying IO capacity
(60..1514). Net composers supply minimum padding. Although IO accepts 14-byte
headers and can pad them, this adapter retains Net's existing submission bounds.
An unprepared/nonpositive source is `Invalid`; positive out-of-range lengths are
`Unsupported`. An occupied adapter is `Busy` before source checks. IO admission
failure is returned without taking a source borrow.

`TrySubmit` reserves the IO fill slot and returns `Accepted`. A background process
then reads the bound source sequentially and appends bytes to IO. Every source and
its dependencies must stay published and unchanged until terminal completion.
Failed reads/appends or rejected commit stop copying, discard the uncommitted fill
and latch `DeviceFailure`. Accepted commit waits for IO completion: `Sent` maps to
`Delivered`; `LinkLost` and `DeviceFailure` map to Net `DeviceFailure`. No further
source reads occur after a terminal result. Results remain until acknowledgment;
acknowledgment clears the underlying IO completion before admitting another frame.

For this backend, `Delivered` occurs after local wire-interface completion. The
common Net contract still means device acceptance and never remote receipt.
Cancellation is unsupported and does not change the borrow. The adapter does not
release or invalidate the source's prepared response; the service owner does that
after completion. Coordinated reset abandons outstanding work and clears metadata;
resetting only the MAC or only a source violates the ownership contract.

## Backend differences

| Property | IO MAC adapter | Existing EthernetLite backend |
| --- | --- | --- |
| Receive storage | IO-owned complete frame; direct scheduled reads | Driver-owned conservative capture prefix |
| Exact received wire length | Known while acquired | Unknown |
| RX FCS | Removed by IO after validation | Excluded from certified prefix |
| Padding | Preserved on RX; Net supplies minimum TX padding | Same frame representation |
| TX terminal success | Local MAC wire completion | Device transmit-mechanism acceptance |
| Link/device failure | Terminal DeviceFailure after local reads stop | Existing driver recovery semantics |

EthernetLite's contracts and implementation are unchanged. The single-slot IO MAC
and scheduled per-byte copies limit application throughput below wire rate;
frames arriving while RX is occupied are dropped whole. Throughput must be
measured for the chosen MAC and application composition.
No new buffering, flow control, CDC or 10M qualification is supplied by this adapter.

## Verification

The package tests `EthernetFrameContractTest` and `EthernetFrameServiceTest` cover
admission bounds, exact receive metadata, ownership and retained completion,
unsupported cancellation, source-copy failure, append/commit failure, link/device
terminal failure and recovery. Existing ARP/ICMP services are checked byte-for-byte
against their fixed independent request/reply vectors. A controllable IO fixture
holds completion to prove the borrow survives after copying ends.

The historical native integration runner (not included in this checkout) additionally
injects physical RMII requests through the real MAC, adapters and existing Net
services. It checks every response dibit and independent zlib FCS, corrupt-frame
rejection, completion after transmission, reset during an active source borrow,
and coordinated-reset reuse in both reset
modes. This establishes simulated integration. Pin constraints, PHY startup,
routed timing and physical link behavior belong to the consuming hardware
composition.
