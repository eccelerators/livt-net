# Packet-storage synthesis probes

These are explicit hardware measurements, not ordinary Livt tests. Run only when
synthesis is requested. Each pair uses identical externally controlled operations,
128-byte source capacity, release generation, a 100 MHz clock constraint and
out-of-context synthesis for xc7a100tcsg324-1. Hold inputs stable until completion
when driving a probe; it is a measurement harness, not a production link adapter.

```sh
LIVT_VIVADO_PATH=/tools/Xilinx/2026.1/Vivado/bin/vivado python3 verification/storage-probes/run.py /tmp/net-storage-measurement
```

The output directory must not exist. `--prepare-only` creates source fixtures
without running Livt or Vivado. Tools can also be selected with `LIVT`.
The script copies the current relevant Net source files into each isolated probe;
it does not modify the library. RAM vs array changes only the storage choice.
The header pair measures an actual 20-byte PacketHeader with the same RAM source,
including its load/read/publication control. The RAM-header variant is experimental.

Measurements on 2026-09-23 with Vivado 2026.1:

| Probe | LUTs | Registers | RAMB18 |
|---|---:|---:|---:|
| 128-byte ArrayPacketData | 1,370 | 2,156 | 0 |
| 128-byte RamPacketData | 1,042 | 1,068 | 1 |
| 20-byte array PacketHeader + RAM source | 1,974 | 2,533 | 1 |
| 20-byte RAM PacketHeader + RAM source | 2,146 | 2,636 | 1 |

The small RAM header used distributed memory (see LUTRAM counts in its report),
so adding RAM does not necessarily add BRAM or reduce total logic. Keep the small
register header caches and share parser instances. Use explicit RAM for larger
snapshots. These are whole-probe totals, not predicted full-board savings or
routed timing claims. Original reports and checkpoints: `/tmp/net022/probes/`.
