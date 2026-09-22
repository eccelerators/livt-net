# Livt.Net Usage

## Parse a configured capture

```livt
using Livt.Net

component EthernetExample
{
    parser: EthernetFrameParser<256>

    new() { this.parser = new EthernetFrameParser<256>() }

    public fn IsIpv4Frame(frame: byte[256], receivedLength: int) bool
    {
        return this.parser.IsIpv4(frame, receivedLength)
    }
}
```

The classifier rejects lengths smaller than its required header or larger than
its configured capacity. Byte getters and builders require initialized request
bytes. Fixed IPv4/TCP headers remain the supported protocol shape.

## Queue a complete response

```livt
using Livt.Net

component FrameIoExample
{
    io: EthernetFrameIo

    new(axi: IAxi4LiteEthernetLiteMaster, mac: in byte[6])
    {
        this.io = new EthernetFrameIo(axi, mac)
    }

    public fn QueueFrame(frame: byte[128], length: int) bool
    {
        if (length <= 0 || length > 128) { return false }
        if (!this.io.TryBeginTxFrame(length)) { return false }
        for (var i = 0; i < length; i++)
        {
            if (!this.io.TryWriteTxByte(i, frame[i])) { return false }
        }
        return this.io.TrySubmitTxFrame()
    }
}
```

Supply one AXI attachment and one application process that serializes lifecycle
calls. Do not change a submitted
frame; wait for `HasTxFrame()` to become false before starting the next one.
Every byte, including application-supplied minimum-frame padding, must be
written. The `Try...` methods report rejected operations; the old void methods
remain source-compatible and ignore rejection.

## Receive and release

Poll `IsFrameAvailable()`. Once true, read indices `0..RX_CAPACITY-1` using
`GetRxByte()` and call `ConsumeRxFrame()` after copying the required bytes.
Default hardware capture is 128 bytes. The captured prefix length is not the
actual wire length; validate protocol lengths before acting on a packet.

Tests can inject a capture by calling `LoadRxByte()` in ascending order for the
entire configured prefix, followed by `SubmitRxFrame()`. Partial injection is
not published. Injection and hardware capture must not overlap. Fixtures that
edit selected fields between packets should keep an explicitly initialized local
`byte[RX_CAPACITY]` array, update that array, then copy every byte in ascending
order before each submission. Consuming a frame invalidates the injected prefix.
Tests that leave TX queued against a stalled slave need separate frame-I/O
instances, or must drive AXI completion before reusing the instance.

## Select storage geometry

```livt
// 256-byte capture, 256-byte RX storage, 512-byte TX storage.
io: EthernetFrameIo<256, 256, 512>
```

Construct it with `new EthernetFrameIo<256, 256, 512>(axi, mac)`. RX capture must
be word aligned and fit its storage. TX lengths must fit both storage and the
EthernetLite data region. Storage cells retain data across reset; only initialized
bytes in the current frame are accessible through the application methods.

## Checksum array APIs

`Ipv4HeaderChecksum.CalculateFixedTcpHeaderChecksumFromBytes` and
`CalculateFixedIcmpHeaderChecksumFromBytes` accept `(totalLength: byte[2],
identification: byte[2], localIp: byte[4], remoteIp: byte[4])`.
All arrays use network byte order (high byte first). The generated header uses
version/IHL 0x45, DF, TTL 64 and the selected TCP or ICMP protocol.

`TcpChecksum.CalculateFixedHeaderChecksumFromBytes` accepts `(localIp: byte[4],
remoteIp: byte[4], localPort: byte[2], remotePort: byte[2], sequence: byte[4],
acknowledgment: byte[4], flags: byte, window: byte[2])`.
`CalculatePayloadChecksumFromBytes` accepts the same fields followed by `tcpLength: int`
and `payloadWordSum: int`. Length includes the fixed 20-byte TCP header; the sum
is from `InternetChecksum.GetWordSum()`, with an odd final byte treated as the
high byte of a word whose low byte is zero. The complete unfolded sum must fit
in a non-negative int (0..2147483647). Empty payloads use length 20 and sum zero.

Existing scalar methods retain their original names and remain available; scalar byte fields must be 0..255.
Both API shapes share the same checksum arithmetic. The array APIs do not
add protocol validation or change supported packet formats.

## Packet data providers

Use `ArrayPacketData`, `RamPacketData` and generic `PacketRegion` for checked,
bounded access to published byte prefixes. See [packet data](packet-data.md) for
construction, ownership and release rules.
