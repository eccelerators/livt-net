# Network services

`NetworkService<S, CAPACITY = 128>` owns the common ARP and ICMP echo response
components. `S` is a stable `IPacketData` request provider, often an acquired
`IFrameReceiver`. The service itself is the `IPacketData` response source.
Construct a transmitter bound to that source and use `FrameService<R, H, T>` to
coordinate reception, handling and transmission. No device or AXI type appears
in the service contract.

## Common composition

This construction is also exercised by `NetworkServiceTest`:

```livt
receiver: TestFrameReceiver<128>
ethernet: EthernetFrameParser<TestFrameReceiver<128>>
ipv4: Ipv4PacketParser<EthernetFrameParser<TestFrameReceiver<128>>>
service: NetworkService<TestFrameReceiver<128>>
transmitter: TestFrameTransmitter<NetworkService<TestFrameReceiver<128>>>
endpoint: FrameService<TestFrameReceiver<128>, NetworkService<TestFrameReceiver<128>>,
    TestFrameTransmitter<NetworkService<TestFrameReceiver<128>>>>

new()
{
    this.receiver = new TestFrameReceiver<128>()
    var mac: byte[6] = [0x00, 0x00, 0x5E, 0x00, 0xFA, 0xCE]
    var ip: byte[4] = [10, 0, 0, 1]
    this.ethernet = new EthernetFrameParser<TestFrameReceiver<128>>(this.receiver)
    this.ipv4 = new Ipv4PacketParser<EthernetFrameParser<TestFrameReceiver<128>>>(this.ethernet)
    this.service = new NetworkService<TestFrameReceiver<128>>(
        this.receiver, this.ethernet, this.ipv4, mac, ip)
    this.transmitter = new TestFrameTransmitter<NetworkService<TestFrameReceiver<128>>>(this.service)
    this.endpoint = new FrameService<TestFrameReceiver<128>, NetworkService<TestFrameReceiver<128>>,
        TestFrameTransmitter<NetworkService<TestFrameReceiver<128>>>>(
            this.receiver, this.service, this.transmitter)
}
```

The long type names describe fixed hardware instances. Applications own this
composition once; they do not prepare each packet header themselves. A real link
replaces the test receiver/transmitter and binds TX to the same response source.
The transmitter must support the complete response length, including Ethernet
minimum-frame padding. FCS remains the MAC's responsibility.

One serialized owner calls `endpoint.Poll()`:

| Result | Meaning |
|---|---|
| `Idle` | No acquired request; nothing submitted |
| `Pending` | Response preparation succeeded, waiting for admission or terminal TX completion |
| `Completed` | Terminal outcome retained; response has been released |
| `Ignored` | No handler accepted the request; RX released |
| `Rejected` | Handling could not prepare a response; RX released |
| `ReceiveFailure` | Receiver reported a device failure; its owner handles device recovery |

Read the retained outcome with `TryGetCompletion(outcome)` and call
`TryAcknowledgeCompletion()` to admit the next request. An outcome of `Delivered`
means the transmitter's local completion contract, not remote delivery or TCP
acknowledgment. `TryCancel()` requests cancellation of an admitted transfer;
keep polling until terminal completion. Cancellation acceptance alone never
releases response storage. Cancellation while awaiting admission returns
`Invalid`.

The coordinator holds one response. It does not acquire a second RX frame during
admission backpressure, transmission or an unacknowledged completion. A link may
retain that second frame according to its own buffering contract. Permanent TX
rejections become terminal `DeviceFailure`; `NotReady`/`Busy` retain the response
and retry admission on a later poll. There is no automatic timeout or retry limit.

## Checked service lifecycle

`IResponseService` extends `IPacketData` with `TryHandle()` and
`TryReleaseResponse()`:

- `Prepared`: a complete response is published and independent of request storage.
- `Ignored`: no response; another handler may inspect this request.
- `NotReady`: the request provider is unavailable.
- `Invalid`: request structure cannot be read safely.
- `Busy`: an existing response remains unchanged; the new request is not handled.

All request views close before `TryHandle()` returns, including failed handling.
The built-in services copy the small required metadata and ICMP payload into
owned response storage, so RX may be released immediately afterward. Headers,
checksums and envelopes are prepared internally. Reads before publication return
`NotReady`; failed reads clear their output byte.

Release only after all response reads and transmitter borrows have ended.
`TryReleaseResponse()` cannot detect references held elsewhere. `FrameService`
enforces the order when it is the sole lifecycle owner. Do not drive its handler
or transmitter independently. All participants must share a coordinated
clock/reset domain and reset together. Reset recovery follows the link contract.

`ResponseTransfer<T>` exposes just the submission/completion portion for callers
that own a response buffer or a different protocol application. Publish the
bound source, call `TryBegin()`, keep it unchanged while polling, and release it
only after `Completed`. Then acknowledge the retained completion. This is how
the Web application retains its HTTP response RAM. It has no background process.

## Shared request parsing

The composition root owns one Ethernet/IPv4 parser pair over the request provider.
`NetworkService` borrows that pair for classification and protocol services.
`ArpService(source, ethernet, policy, mac, ip)` and
`IcmpEchoService(source, ethernet, ipv4, policy, mac, ip)` lend their validated
views to response preparation, avoiding another header read or parser instance.
All supplied parsers must bind the same capture and share a clock/reset domain.
Serialize their use; invalidate external descendants (such as TCP parsing) before
handling another request or clearing diagnostics. These are fixed hardware
bindings, not dynamically selected parser objects.

`IcmpEchoResponder` retains echo bytes in `RamPacketData<CAPACITY>` so successful
responses remain independent of RX. The common Web endpoint uses one receive RAM
for HTTP and these services; it no longer duplicates every frame into two arrays.

## Custom policies and handlers

`ArpService<S, A>` and `IcmpEchoService<S, A, CAPACITY = 128>` borrow an
`IFrameAcceptance` strategy. `Accept(sourceMac, etherType)` adds a policy check
using validated Ethernet metadata. `AcceptAllFrames` supplies the common default;
protocol shape and local destination checks still apply. `TrustedPeer` in the
tests demonstrates a source-MAC policy shared by both services.

Compose fixed instances using `ServiceChain<First, Second>`. Only `Ignored`
falls through to `Second`. A prepared response selects its handler until release;
`Busy` preserves the selection and bytes. Chains can be nested to add handlers
without modifying packet encoders or drivers. Custom handlers implement the same
snapshot and response-ownership contract. Do not independently mutate a selected
child. There are no stored callbacks or dynamic component references.

Existing packet composition remains available for custom payloads and generators:
see [packet composition](packet-composition.md). A custom service can own one of
those graphs and expose it through `IResponseService`.

## Scope and diagnostics

The built-in service supports the existing Ethernet/IPv4 ARP and fixed-header
ICMP echo subset. The echo responder’s storage and Ethernet payload limit use `CAPACITY`
(minimum 42); incomplete, oversized or unsupported requests do not produce a response. This preserves the existing
[parser and checksum policy](packet-parsing.md), including its input-validation
limits; it does not add a fully general TCP/IP stack or input checksum validation.

`FrameClassification<S>` snapshots Ethernet/IPv4 protocol and local-IP metadata,
then closes all views. It distinguishes classification from response acceptance:
a captured IPv4 header can be classified even when its body cannot be handled.
`NetworkService` retains those diagnostics until the next request or an idle
`ClearDiagnostics()`. Busy handling leaves them unchanged.

Livt.Web's `NetworkEndpoint` uses this common service for ARP/ICMP and protocol
diagnostics. HTTP routing, content configuration and the existing narrow TCP
connection behavior remain in Livt.Web. Its `BeginFrame()` ends the previous
response lifetime; callers must finish response reads first.
