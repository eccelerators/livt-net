# EthernetLite driver migration draft

This is an **unpromoted, failing development draft**. Production Net/Web/WebApp
sources retain their accepted baseline. Do not apply the migration patches until
the live-pin compiler regression and complete driver acceptance tests pass.

The standalone project contains the proposed device driver, RX/TX ownership
components, shared AXI word sequencer and a Livt slave fixture. Run:

```sh
livt test -f --events
```

Current focused result: **1 passed, 1 failed**. The CRC-window test passes; the
independent-channel handshake assertion fails during MAC programming because a
borrowed component's live pins acquire register stages. Do not add handshake
waits or relax assertions to mask this problem.

The full migration is preserved in `patches/net.patch`, `patches/web.patch` and
`patches/webapp.patch`. Apply each from its corresponding repository root after
checking `git apply --check`; they target the working-tree contents from the NET-014
session, including earlier uncommitted Web/App work. File lists and baseline
fingerprints accompany them. Generated lock/cache/build files are excluded.

## Proposed design

- `EthernetLiteReceiver` owns RAM capture/acquisition; `EthernetLiteTransmitter<S>`
  borrows a prepared packet source until a terminal result.
- `EthernetLiteDriver<B, S>` owns MAC programming, polling and register sequencing.
  `EthernetLiteBus` adapts the board interface to `EthernetLiteTransactions`.
  AXI accepts AW/W independently, zero-pads final word lanes and checks R/B errors.
- A bounded CRC scan excludes FCS/retained memory after a shorter receive. It
  certifies only a prefix and leaves wire length unknown. See `docs/ethernetlite.md`.
- Web fixtures use device-independent test links. `WebApplication<R, T>` owns
  protocol/application logic; `WebApp` is the concrete board composition root.
  The proposed wrapper updates its interface package and removes diagnostic ports.

## Evidence

- Final draft Net: **88/89 passed, 1 failed, 0 skipped**,
  `/tmp/net014-net-final.log`. The failure is the AXI handshake regression.
- Draft Web: **36/36**, `/tmp/net014-web.log`.
- Final draft WebApp: **17/17**, `/tmp/net014-webapp-final.log`, including a complete
  independently expected ARP reply and source retention through backpressure.
- Standalone receive-window checks cover all four FCS alignments, retained-tail
  exclusion and prefix truncation, using CRC vectors computed independently.
- Compiler regression `testBorrowedComponentLivePins`: **1 passed, 1 failed**.
  The identical owned-component control passes; adding a scheduled-method borrower
  delays the separately connected pins. This is compiler issue #523.
- Related minimal findings: #520 opposite interface borrowers (1 passed, 2 failed),
  #521 stored reset-typed field accessor syntax (logic-signal reset control passes),
  and #522 constructor output-field projection (generated input record is wrong).
  Regressions live under `livt-gen-vhdl-verification/tests`, not in this package.

The driver test has not reached its later TX/RX/error assertions; their presence
is not passing coverage. The previous native AXI/board results apply to the old
implementation. No synthesis, native harness, bitstream, flash or board test ran.

## Resume

1. Fix/verify `tests/ConstructorTests/testBorrowedComponentLivePins` in the compiler
   regression repository. Keep the assertion that live pins have no extra stages.
2. Rerun this standalone project. Complete the driver checks for MAC completion,
   both channel orders/stalls, initialized source bounds, zero tail lanes,
   completion retention, unknown-length RX, shorter reuse and AXI errors/recovery.
3. Add/finish source-read-failure and coordinated in-flight reset regressions.
   The separate logic-signal clock/reset probe passes; that is not a full driver
   reset test. Resolve any newly exposed failures before promotion.
4. Reapply the patches in isolated snapshots, refresh dependencies and rerun the
   owning Net/Web/WebApp Livt suites. Audit the inactive legacy
   `WebAppAxiIntegrationTest` (its synthetic frames lack FCS); it is not current
   acceptance evidence. Review the bounded-CRC capture policy and API documentation.
5. Promote verified files together, refresh consumer locks and remove this duplicate
   draft. Do not close the extraction or its enum cleanup merely because patches exist.

## Design-guide cleanup after this draft

The production Net source/tests received a comment and whitespace cleanup under
NET-019. The original `net.patch` and runnable draft are intentionally unchanged.
Its original existing-file base is retained in `patches/net-base/` and matches
`baseline-hashes.json`. Rebase that patch onto the cleaned source before resuming;
do not overwrite the cleanup with the old patch. Web/App patches are unaffected.
