# Ethernet verification

The ordinary Livt suite covers protocol behavior, buffer validity and independent
capacity specializations. The native GHDL bench checks AXI acceptance at clock
edges, independently of scheduled diagnostic getter calls.

```sh
livt test
livt test -R
livt test -O none
livt test -R -O none
python3 verification/ethernet/configurations.py
python3 verification/ethernet/run.py --generated out/debug
python3 verification/ethernet/run.py --generated out/release
python3 verification/ethernet/matrix.py
```

Set `LIVT_GHDL_PATH` or pass `--ghdl` to the native runner when GHDL is not on
PATH. Build the desired configuration before running its native checks; the
runner uses the existing generated output and does not rebuild or edit it.
`--reset-style sync` or `--reset-style async` selects the DUT's existing reset
generic; omitting it tests the generated default. `matrix.py` rebuilds debug and
release with default optimizations and `-O none`, then checks both reset policies
for each build. It preserves source files and package pins and prints the log
directory for all eight cases. The focused compiler fixture separately verifies
the CLI's `--default-reset-style` generation under the same combinations.
Negative configuration checks run both `livt validate --json` and
`livt build --json` on isolated source snapshots. Each command must return a
nonzero exit status, `success: false`, and a source-located failed-static-assert
diagnostic. Internal diagnostic-conversion failures are not successful rejections.

The native runner writes its generated harness and logs to a printed temporary
directory. It fails on any GHDL error or missing completion marker. It covers:

- independent, staggered AW/W acceptance and delayed R/B responses;
- request stability under backpressure and duplicate acceptance;
- TX queued before MAC programming completes;
- TX lengths 1, 2, 3, 4, 5, 60 and 2036, then reuse for a one-byte frame;
- exact payload bytes, low-byte-first packing, zero final-word padding, bounds,
  length/control ordering and completion;
- ping and pong RX payload capture, release after all words, consumption,
  availability and invalid reads;
- reset with stalled device work, reset during an API RAM write, interrupted RX
  capture, invalidation of retained data, and a fresh transmission after reset.

The fixed native bench uses default FrameIo geometry. The Livt capacity tests
exercise 64/256-byte RX captures and 5/512-byte TX storage; the five-byte depth
also exercises non-power-of-two memory geometry. Protocol tests specialize
complete child-component graphs to 96 and 256 bytes.

## Verified borrowed-interface boundary

Compiler issue #491 is verified on 2026-09-21: all eight native combinations
(debug/release, default/no optimizations, synchronous/asynchronous reset) pass on
unmodified generated HDL, each completing at 1,604,176 ns. Constructor-borrowed
combinational signal interfaces no longer insert independent READY/VALID delays.
The earlier compiler failed at 1045 ns with `AR changed under stall`; that result
and the diagnostic-only HDL experiment remain recorded in the migration evidence.
No generated-HDL patch or library workaround is needed for this fix.

See [migration evidence](../../docs/migration-evidence.md) for tool identities,
commands, actual results and consumer compatibility findings. FPGA mapping,
resources and timing closure have not been measured. Keep the scheduled storage
implementation until transfer correctness and a measured application performance
budget justify a separate hardware-core change.

## Verified invalid-capacity boundary

Compiler issue #492 is verified on 2026-09-21: all 12 invalid configurations are
rejected correctly by both commands (24 checks), including zero TX capacity.
The ordinary valid Livt suite still passes all 56 tests. The earlier compiler's
accepted configurations and null-node diagnostic conversion are recorded as
historical failures in the migration evidence. Development web-app UART integration
is now verified with #497; see the consumer results linked from that evidence.
