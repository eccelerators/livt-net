# Packet-data prototype promoted

The NET-012 packet providers and bounded regions are now in `src/packet` at the
package root. Their six Livt tests are registered as `PacketDataTest` in the
normal package; API documentation is in `docs/packet-data.md`.

Run `livt test -r PacketDataTest` from the Livt.Net root. This directory no longer
contains a separate project or duplicate sources. Compiler #513 originally
blocked the draft; the unchanged six tests passed after that fix before promotion.
Historical failure logs are recorded in the internal project tracker.
