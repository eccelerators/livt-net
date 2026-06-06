# Livt.Net Usage

These examples show the intended call order for the current fixed-size
`Livt.Net` APIs. They are intentionally small and omit application-specific
content loading.

## Parse an Ethernet Frame

```livt
using Livt.Net

component EthernetExample
{
    parser: EthernetFrameParser

    new()
    {
        this.parser = new EthernetFrameParser()
    }

    public fn IsIpv4Frame(frame: byte[64]) bool
    {
        return this.parser.IsIpv4(frame)
    }
}
```

## Recognize an ARP Request

```livt
using Livt.Net

component ArpExample
{
    responder: ArpResponder

    new()
    {
        this.responder = new ArpResponder()
    }

    public fn ShouldReply(frame: byte[64], localIp: byte[4]) bool
    {
        return this.responder.ShouldRespond(frame, localIp)
    }
}
```

## Build an Endpoint Response

```livt
using Livt.Net

component EndpointExample
{
    endpoint: NetworkEndpoint

    new()
    {
        var mac: byte[6] = [0x02, 0x00, 0x00, 0x00, 0x00, 0x01]
        var ip: byte[4] = [0x0A, 0x00, 0x00, 0x01]
        var port: byte[2] = [0x00, 0x50]

        this.endpoint = new NetworkEndpoint(mac, ip, port)
    }

    public fn LoadAndHandleFirstByte(value: byte) bool
    {
        this.endpoint.BeginFrame()
        this.endpoint.LoadRxByte(0, value)
        this.endpoint.HandleFrame()
        return this.endpoint.HasResponse()
    }
}
```

`NetworkEndpoint` expects the caller to copy the complete received frame before
`HandleFrame()` is called. `GetResponseByte(index, httpBodyByte)` returns one
selected response byte at a time.

## Configure HTTP Body Metadata

```livt
using Livt.Net

component HttpExample
{
    server: WebServer

    new()
    {
        var mac: byte[6] = [0x02, 0x00, 0x00, 0x00, 0x00, 0x01]
        var ip: byte[4] = [0x0A, 0x00, 0x00, 0x01]
        var port: byte[2] = [0x00, 0x50]

        this.server = new WebServer(mac, ip, port)
        this.server.SetBodyConfig(1, 64, 717318)
    }

    public fn GetResponseByte(index: int, bodyByte: byte) logic[8]
    {
        return this.server.GetResponseByte(index, bodyByte)
    }
}
```

HTTP body bytes are supplied by the caller. `SetBodyConfig(route, length,
checksumWordSum)` supplies the metadata needed by response checksum generation.

## AXI4-Lite EthernetLite Boundary

```livt
using Livt.Net

component FrameIoExample
{
    io: EthernetFrameIo

    new()
    {
        var mac: byte[6] = [0x02, 0x00, 0x00, 0x00, 0x00, 0x01]
        this.io = new EthernetFrameIo(mac)
    }

    public fn QueueByte(value: byte)
    {
        this.io.BeginTxFrame(60)
        this.io.WriteTxByte(0, value)
        this.io.SubmitTxFrame()
    }
}
```

The AXI adapter exposes hardware-facing signals through
`IAxi4LiteEthernetLiteMaster`. Frame-level callers should prefer the
`EthernetFrameIo` methods unless they are building a direct EthernetLite
integration.
