# Livt.Net 1.1.0-dev migration evidence

Review date: 2026-09-21. Native AXI verification passes with the #491 compiler
fix, and invalid-capacity rejection passes with #492. Development web-app integration
is verified with #497. Package publication and physical hardware validation are
not claimed.

## Inputs

- Livt.Net baseline: `8f51640` (1.0.1), plus the user's IO 1.2.0-dev pin.
- Livt.IO source: `b18f5e9` (1.2.0-dev). The resolved memory source directory
  matches the sibling working-tree memory sources byte for byte.
- Resolved transitive dependency: Livt.Collections 1.1.0-dev.
- The original reviewed CLI and generator reported `v0.0.0-0000000`; baseline hashes:
  - `livt.jar`: `e03114bf6611caa4454c6c09a85c95937391cf3187cbff4c224d459916b9b37b`
  - `livt-gen-vhdl.jar`: `8374e89c105b54f6efb174a4132bdd0e49b4023046308bef9f794edf3ddbcd15`
- GHDL: 6.0.0 (`6.0.0.r0.ge589c698c`), GCC backend, GNAT 13.3.0.
- Test context: 100 MHz. Default synchronous reset unless explicitly selected.

## Baseline and migration

The old baseline copied original Net sources/tests and IO's `1.0.1` tag into
`/tmp/livt-net-old-baseline`; the user's working-tree dependency pin was not
changed. `livt test --json` passed all 50 original tests. Log:
`/tmp/livt-net-old-baseline-run.log`.

Before migration the current IO dependency failed source validation on the
nongeneric RAM API (`/tmp/livt-net-current-baseline.log`). After the initial
scheduled RAM migration the same 50 tests passed
(`/tmp/livt-net-migration-run.log`).

The completed generic APIs, checked buffer lifecycle and new tests pass all 56
Livt tests in debug/default-optimization mode (`/tmp/livt-net-generics.log`).
Additional mode results are recorded below.

## API and compiler compatibility choices

- Generic frame storage now uses concrete `Ram<byte, RX_STORAGE_CAPACITY>` and
  `Ram<byte, TX_STORAGE_CAPACITY>` fields. Compiler #494 preserves projected
  member signatures while specializing the enclosing component. The former
  `IRam<byte>` field workaround is removed; construction and scheduled RAM
  semantics are unchanged. Interfaces remain available as an API design choice.
- Length-aware classifiers now use `validLength: int = FRAME_CAPACITY` with the
  #493 generator fix. Originally an unbound `FRAME_CAPACITY` identifier escaped
  into calling HDL, requiring forwarding overloads. The 20 workaround wrappers
  in Ethernet/ARP/IPv4/TCP parsers have been removed; omitted and explicit-length
  call shapes are preserved.
- `EthernetFrameBufferTest` now reuses one constructor-local MAC array for both
  children. Compiler #495 gives the shared value one parent-owned declaration,
  removing the separate-array workaround. With the fix installed, `livt test -f -v`
  passes all 56 tests (2026-09-22; `/tmp/livt495-net.log`). This rerun covers the
  Livt simulation suite, not physical hardware or the separate native AXI matrix.
- Compatibility wrappers now call their checked methods directly and discard
  the boolean results. Compiler #496 preserves scheduled completion without
  treating a discarded result as an enclosing component-field assignment. The
  former local-result/early-return workaround has been removed from
  `BeginTxFrame`, `WriteTxByte`, and `SubmitTxFrame`. With the fix installed,
  `livt test -f -v` passes Net 56/56 and Web 34/34 on 2026-09-22
  (`/tmp/livt496-net.log`, `/tmp/livt496-web.log`). These are Livt/GHDL results,
  not a rerun of the native AXI matrix or physical hardware verification.
- AXI signal access is isolated in an explicit combinational wiring process.
  Compiler issue #491 now preserves that wiring through the borrowed interface,
  without extending test waits or requiring nonstandard READY behavior.

## Native AXI gate

Original command: `python3 verification/ethernet/run.py --ghdl /home/vagrant/ghdl/bin/ghdl`.
Before #491, unmodified debug HDL failed at 1045 ns: `AR changed under stall`.
Evidence: `/tmp/livt-net-ethernet-581ri_vl/2.log`. The earlier bench, before adding
the pre-MAC-initialization TX queue scenario, failed at 115 ns.

A diagnostic-only generated-HDL copy with direct borrowed-interface wiring passes
TX queued before MAC initialization, TX/RX, partial-word padding, backpressure,
pending-write reset, interrupted-RX reset and restart. Evidence:
`/tmp/livt-net-ethernet-gg4x8kqq/2.log`. It completes at 1,604,176 ns.
The queued-frame scenario caught and fixed startup code that cleared pending TX
when MAC programming completed. These results cannot establish shipped performance:
no timing/throughput guarantee or physical resource claim is made for Net.
The compiler fix and unmodified-HDL rerun are now verified below.

### Compiler #491 verification

The generator fix is based on `livt-gen-vhdl` revision `4efd55722` plus the #491
working-tree changes; language baseline `5abdec6` is unchanged. The installed
generator SHA-256 is
`e137e4ce9ebc0fe7fc7c9ff375d83bda054b330c3e19dd45d17f2b16f8ad07f8`.
Livt.Net source and package pins were not changed for this fix. GHDL and the
100 MHz test context are as listed above.

Command:
`python3 verification/ethernet/matrix.py --ghdl /home/vagrant/ghdl/bin/ghdl`.
All eight native configurations pass on unmodified generated VHDL:

| Profile | Optimizations | Sync reset | Async reset |
|---------|---------------|------------|-------------|
| Debug | Default | Pass | Pass |
| Debug | None | Pass | Pass |
| Release | Default | Pass | Pass |
| Release | None | Pass | Pass |

Every simulation completes at 1,604,176 ns. The existing bench checks independent
AW/W acceptance, delayed responses, backpressure, exact payload and padding,
RX ping/pong, queued startup TX and reset recovery. Reset variants select the
DUT's reset-policy generic; generated HDL is never patched. Build and simulation
logs: `/tmp/livt-net-ethernet-matrix-xg55740u`.

The self-contained compiler fixture
`testBorrowedSignalInterfaceWiring` additionally passes 9,216 stopped-clock
signal comparisons per configuration, including during reset, in all eight
profile/optimization/CLI-reset-default combinations. Its header-free output is
mirrored into generator snapshots. `make install` passes 2,593 generator tests
(six existing skips) including 676 verification fixtures, plus the packaged
extension checks. Build log: `/tmp/livt491-gen-full1.log`.
The ordinary `livt test -O none` suite also passes all 56 tests with this artifact
(`/tmp/livt491-net-tests.log`).

These results establish the tested handshake and reset semantics, not physical
area, timing closure, sustained-throughput guarantees or board readiness.

## Consumer integration

A snapshot of `livt-web-app` and its cached dependencies was staged at
`/tmp/livt-net-web-integration`, replacing Net and IO with the reviewed sources
and remapping all dependencies to local snapshot paths. No application pin was
changed. `livt test --json` fails before simulation: WebApp still uses the old
UART constructor and `Send`, `Transmit`, and `GetTransmitSpace` methods. All 16
application tests are skipped. Log: `/tmp/livt-net-web-integration.log`.

That app's direct IO 0.2.0-to-1.2.0-dev UART migration is separate from the Net
memory migration. Its original Net 0.26.0 pin also means an ordinary application
build does not test this Net working tree. Integration cannot be marked passed
until the UART consumer is migrated and the staged tests rerun.

### Livt.Web library fixtures

The isolated old-dependency Livt.Web 0.1.0 baseline passes 34/34 tests
(`/tmp/livt-net-web-baseline.log`). With the new dependencies and unchanged Web
fixtures, 27 pass, two fail and five are skipped
(`/tmp/livt-net-web-library-wrapper.log`). The failing fixtures depend on sparse
RX injection and frame reuse while an earlier TX remains queued against an
unserviced AXI slave.

An isolated fixture migration retains packet bytes in a local array and copies
all 128 bytes in order before every RX submission. The ARP and HTTP TX checks
use separate frame-I/O instances because their dummy slaves never complete TX.
The exact fixture-only patch is `/tmp/livt-net-web-fixture-migration.patch`;
no published dependency cache or application source was edited.
The migrated fixtures pass **34/34 tests**, with no failures or skips
(`/tmp/livt-net-web-fixtures.log`). Web production source required no changes.
This clears the isolated Web library check, while the app UART gate remains open.

## Invalid-capacity gate

Historical failure before #492: `EthernetFrameParser<13>` was not rejected despite
its minimum-14 static assertion. `livt validate` reports success. `livt build`
logs a null-node exception in `DiagnosticConverterImpl`/`NodeModelUtils` while
converting the specialized assertion diagnostic, then reports success and emits
HDL. Initial evidence: `/tmp/livt-net-invalid-kyt01pf3/case-0.log`. The negative
configuration script requires an actual static-assert diagnostic and failing
exit status; it does not count unrelated crashes as a passing rejection.

### Compiler #492 verification

The fix uses `livt-lang` baseline `5abdec6` plus the #492 working-tree changes,
CLI baseline `fc9583a` plus its diagnostic regression, and generator baseline
`dd83dc56d` plus the updated positive fixture snapshots. The rebuilt CLI and
generator are installed locally. SHA-256 identities:

- `livt.jar`: `bc422822ab06740d48cfae32149fcfc2542c5fcd72841198fabec6c797402b4f`
- `livt-gen-vhdl.jar`: `d6532e4edf02d11f90ad410bfffabc3f38a7742a9e2080eabc2103cabeca98fe`

`python3 verification/ethernet/configurations.py` now checks both
`livt validate --json` and `livt build --json`. All 12 invalid configurations
are rejected correctly by both commands (24 checks), including zero TX capacity.
Each rejection has a nonzero exit, `success: false`, and a source-located
failed-static-assert diagnostic, with no internal conversion exception.
Evidence: `/tmp/livt-net-invalid-u269kma8/summary.json` and its command logs.
`livt test -f` also passes all 56 valid Net tests in debug/default mode
(`/tmp/livt492-net-positive.log`), with the same GHDL/context as above.

The compiler-owned negative harness in
`livt-gen-vhdl-verification/validation/testGenericStaticAssertions` passes all
31 CLI checks: minimum/zero/negative/alignment/default/forwarded values, repeated
rejections, debug/release with default/no optimizations, no fresh rejected output,
and valid-invalid-valid recovery. Evidence: `/tmp/livt-generic-contracts-ggzux6rn`.
The header-free positive `tests/StatementTests/testStaticAssert` fixture passes
all four profile/optimization combinations at 815 ns and is mirrored into the
generator's exact-output regression suite. Full language, CLI and generator
`make install` runs pass without failures (2,080 / 441 / 2,593 tests respectively,
with 10 / 1 / 6 existing skips), including all 676 generator verification fixtures
and two additional packaged-extension tests. Logs: `/tmp/livt492-lang-full.log`,
`/tmp/livt492-cli2.log`, `/tmp/livt492-gen-full.log`.

This clears the invalid-capacity compiler gate. It does not clear the separate
web-app UART migration or establish physical resource/timing results.

### Compiler #493 verification

The generator fix uses `livt-gen-vhdl` baseline `115536f97` plus the #493
working-tree changes. Language `9586da3` and CLI `fc20db7` are unchanged by this
fix. Final installed artifact SHA-256 identities:

- `livt.jar`: `3d3f8df67ee6df48149ae570ade127938b84280dd7fb2a37c5cd9c6b41a46ddc`
- `livt-gen-vhdl.jar`: `0d7385b3397ee4c90a690b2db2e15e51919a2c628b97446e3c070f64fca4112c`

Defaults referencing a receiver's specialized scalar constants now emit typed
initializers in the caller. Same-component defaults retain their constant names.
The exact-output unit regression compares complete functions against explicit
arguments at two capacities and across repeated generation. The self-contained,
header-free `testDefaultParameterValues` fixture covers local-package calls,
inherited/forwarded values, 64/96/128/256 capacities, explicit/named overrides,
arithmetic/grouping, and signed/unsigned/boolean defaults. Final-artifact commands
`livt test -f`, `livt test -f -R`, `livt test -f -O none` and
`livt test -f -R -O none` all pass at 1,895 ns
(`/tmp/livt493-matrix-final.log`). Default-profile sources and VHDL are mirrored
into the generator's exact-output fixtures.

Full generator `make install` passes 2,594 tests, with six existing skips and no
failures, including all 676 verification fixtures, plus two packaged-extension
checks. Log: `/tmp/livt493-gen-full2.log`. `make copy-to-home` installs that artifact.

Net uses `validLength: int = FRAME_CAPACITY` in 20 classifier methods across
Ethernet/ARP/IPv4/TCP parsers. The forwarding workaround overloads are removed;
omitted and explicit-length call shapes and existing bounds checks remain.
With the final installed artifact, `livt test -f` passes all 56 tests in
debug/default mode (`/tmp/livt493-net-final.log`). GHDL and the 100 MHz context
remain as listed above. `python3 verification/ethernet/configurations.py` rejects
all 12 invalid configurations in validation and build (24 checks;
`/tmp/livt-net-invalid-bchpc17r/summary.json`). No dependency pins changed.

A concurrent WebApp packaging report used the older isolated toolchain and found
unbound `FRAME_CAPACITY` in HTTP recognition and classifier callers. A temporary
app source/board snapshot at `/tmp/livt493-webapp-WAaWte/livt-web-app`, with its
declared dependencies and the final generator above, passes `livt build -R -f`.
GHDL `-i --std=08` imports the generated release HDL and handwritten wrapper;
`-m --std=08 webapp_wrapper` succeeds. Logs: `/tmp/livt493-webapp-build.log`,
`/tmp/livt493-webapp-ghdl.log`. The existing variable-divisor warning is unchanged.
The original packaged IP and board project remain untouched: regenerate and
recheck the package with the fixed toolchain before board use.

Removing a forwarding overload removes a scheduled call boundary; the default
itself adds no extra call or runtime selection. These checks establish behavior
and legal HDL, not physical resource savings, timing closure or throughput gains.
The earlier #491/#497 integration matrices remain historical evidence for their
recorded configurations; their complete matrices were not rerun for #493.

## Installation change during verification

The installed generator changed while unoptimized tests were running. That run
failed with `ZipFile invalid LOC header (bad signature)` and is invalid as a Net
regression result. A verified copy of CLI and extension JARs was then isolated
under `/tmp/livt-net-toolchain`, with normal license access and separate logs.
The new VHDL generator SHA-256 is
`3d90d450791643c188f95a9f19c77cc4a7822245dba5a68d31d912175631fa7d`.
The CLI hash is unchanged. Stable-toolchain mode results follow below.

## Verification matrix

| Configuration | Result | Log |
| --- | --- | --- |
| Old IO baseline, debug | 50/50 passed | `/tmp/livt-net-old-baseline-run.log` |
| Migrated source, debug/default optimizations | 56/56 passed | `/tmp/livt-net-generics.log` |
| Stable tool snapshot, release/default optimizations | 56/56 passed | `/tmp/livt-net-release-stable.log` |
| Stable tool snapshot, debug/`-O none` | 56/56 passed | `/tmp/livt-net-noopt-stable.log` |
| Stable tool snapshot, release/`-O none` | 56/56 passed | `/tmp/livt-net-noopt-release-stable.log` |

The final source was rerun in full debug mode: **56/56 passed**
(`/tmp/livt-net-final-suite.log`). After the final compatibility-wrapper and
MAC-startup fixes, the focused four-test buffer suite passed in all four modes
(`/tmp/livt-net-frame-final-{debug,release,noopt,release-noopt}.log`).

The release run includes the generic test helper marked `@Test`, preserving its
assertions in release output. All four modes pass. Ordinary behavioral test passes do not clear the native AXI
gate. Unmodified stable release HDL and debug/`-O none` HDL both reproduce the
115 ns native AXI failure.

Before #492, the complete negative matrix failed all 12 checks: 11 invalid specializations
were accepted; zero TX capacity failed through an unrelated compiler diagnostic,
not the required static assertion. Evidence:
`/tmp/livt-net-invalid-tv3m86iz/summary.json`. The test script exits nonzero.

Generated-HDL inspection found the expected byte RAM depths 5, 64, 256, 512 and
2048, with no whole-array storage assignment/reset in those synchronous cores.
The default FrameIo instantiates two scheduled 2048-byte RAMs. This is structural
HDL evidence, not a synthesis mapping or timing report.

## Consumer #497 verification

The migrated app passes all 16 tests in debug and release, and the restored
Livt.Web checkout contains the updated fixtures (34/34 tests pass). Net's 56 tests,
both native reset variants and all 24 invalid-capacity checks pass again with the
current isolated compiler. UART banner/reset checks pass on unmodified app HDL
in debug and release at 10 MHz / 115200 baud. The earlier 100 MHz UART simulation
hit its wall-clock timeout and is not a passing result.

The app uses explicit sibling IO, Net, Web and Base development dependencies;
Base 1.1.0 resolves an older transitive package's `match` keyword conflict.
See [consumer migration evidence](../../livt-web-app/verification/migration-evidence.md)
for tool identities, logs and limits. This clears development consumer integration;
package publication, board deployment and physical timing/resource measurements
are separate work. Earlier failures above are historical evidence.

## Concrete RAM member lookup — #494

Verified 2026-09-21/22. `EthernetFrameIo` now declares its two private storage
fields as `Ram<byte, RX_STORAGE_CAPACITY>` and `Ram<byte, TX_STORAGE_CAPACITY>`.
The old compiler reproduced `Member 'Write' does not exist` on these fields
(`/tmp/livt494-net-baseline.log`). The fixed language frontend preserves receiver
member projections while copying generic owners; the CLI must be rebuilt to
include that frontend. No RAM construction, capacity, scheduling or reset
semantics changed.

Source baselines: language `9586da3` plus the #494 fix, generator `a7c80a6b9`,
CLI `fc20db7`, and Net `8f51640` plus the migration working tree. Dependencies
remain those resolved by Net's existing Livt.IO 1.2.0-dev manifest/lock.
GHDL: 6.0.0 (`6.0.0.r0.ge589c698c`).

| Check | Result | Evidence |
|-------|--------|----------|
| `livt test -f`, debug/default optimization | 56/56 passed | `/tmp/livt494-net-final2.log` |
| `python3 verification/ethernet/configurations.py` | 24/24 validation/build rejections passed | `/tmp/livt494-net-invalid.log`; `/tmp/livt-net-invalid-fu6g11rk/summary.json` |
| Native AXI, `--reset-style sync` | Passed on generated HDL | `/tmp/livt494-net-native-sync.log` |
| Native AXI, `--reset-style async` | Passed on generated HDL | `/tmp/livt494-net-native-async.log` |

Native commands use `python3 verification/ethernet/run.py --ghdl
/home/vagrant/ghdl/bin/ghdl --reset-style <sync|async>`. CLI SHA-256:
`8230a1c75a87744a65be73458722000617cbde8c00b4664206deaf40e1506d4c`.
The generator used for the Net checks had SHA-256
`999a62d4771d3eb3d9372e959ac541e7fa4c11a216f35750281b98bc9b45f794`.
After exporting the new regression, the final generator build passed all 2,595
tests (677 verification fixtures); its installed artifact is
`112ec08527819905c84c2dd5ed6e2f9c7a569dd175732dfb3618c91089dd53ba`.
No generator implementation source changed between these builds. The final
installed artifact also passed the focused GHDL regression
(`/tmp/livt494-fixture-installed.log`).

The compiler-owned header-free `testForwardedStorageMembers` fixture passes in
debug/release with default and disabled optimizations and is mirrored into the
generator's exact-output tests. The separate implementation-only overload naming
failure on an owned interface field is tracked as #503, not claimed fixed by
#494. These checks do not establish FPGA synthesis, timing or area.
