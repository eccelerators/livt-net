# Generic packet prototype promoted

Packet composition now lives in the normal `src/packet` directory. Tests are
registered as GenericPacketTest and PacketMetadataTest. Run `livt test` from the
Livt.Net root. This directory retains no duplicate implementation.
