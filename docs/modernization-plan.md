# Livt.Net modernization plan

Status: implemented in the working tree. Compiler gates #491/#492 and development
consumer integration #497 are verified. Package publication and physical hardware
measurements remain separate work.
See [migration evidence](migration-evidence.md) for verified results and limitations.

Implemented: generic scheduled RAM, checked TX lifecycle, initialized-prefix
tracking, zero final-word padding, safe register bounds, configurable protocol
and storage capacities, defaulted classifier lengths, API/configuration/native
AXI regressions, development version and documentation. Native transfer correctness
is verified; throughput budgets and a lower-level storage-core decision still
require application measurements.
Reviewed 2026-09-21 against Livt.Net `8f51640`, Livt.IO `b18f5e9`
(1.2.0-dev), and the current livt-project working tree.

## Objective

Update Livt.Net to the generic Livt.IO memory API and use compile-time
configuration where it improves reuse without hiding hardware costs. Preserve
the existing Ethernet II, fixed-header IPv4/TCP, ARP and ICMP scope. Deliver the
memory migration before broadening the public configuration surface.

## Findings and design inputs

- The existing local change to `livt.toml` already selects Livt.IO 1.2.0-dev.
  Preserve it. Livt.Net still identifies itself as 1.0.1.
- Only `src/EthernetFrameIo.lvt` directly uses Livt.IO: two nongeneric `Ram`
  fields, two constructors and eleven `ReadByte`/`WriteByte` calls.
- New `Ram<T, CAPACITY, STYLE>` defaults to 64 elements, not the old 2048
  bytes. Its methods are `Read` and `Write`. Cells are unspecified until written
  and survive reset; calls are scheduled over a shared synchronous port.
- Frame I/O currently captures 32 RX words (128 bytes), owns a separate
  injected-RX `byte[128]`, and transmits up to 511 words (2044 bytes).
  Its final TX word always reads four cells, including cells beyond the declared
  length. Oversized lengths are not consistently bounded: word count is capped
  but the original length is still written to the device.
- Protocol helper arrays are fixed at 64 or 128 bytes. These are useful
  candidates for value parameters; the network byte type itself should remain
  `byte`, with `logic[N]` at hardware boundaries.
- `EthernetFrameIoTest` has one test, covering MAC programming and the idle
  no-frame path. It does not establish payload-transfer, padding or reset safety.
- README still describes Livt.IO 1.0.1; hardware notes reference removed
  `InternalRam` HDL; the README flow mentions a nonexistent `BeginFrame()`.

Design authority:

- [Project goals and measured contracts](../../livt-project/README.md).
- [Compiler tracker](../../livt-project/releases/1.1.0/COMPILER.md): #397
  generics, #400 static assertions, #402 constraints, #423 component value
  parameters, #447 width calculations, #448 reset semantics, #455 memory
  migration and #456 portable memory lowering.
- [Livt.IO memory contract and migration guide](../../livt-io/docs/memory.md).

## 1. Establish a reproducible baseline

1. Record compiler/generator versions, dependency resolutions and source
   revisions. Verify the selected 1.2.0-dev package contains the reviewed generic
   API; a mutable development version alone is not a reproducible identity.
2. Run the existing 17 configured test components against the previous dependency
   in an isolated snapshot, then capture current-dependency diagnostics. Do not
   overwrite the user's manifest change to obtain the baseline.
3. Record the old frame-I/O generated storage and transfer timing where feasible.
   Confirm actual AXI byte-lane order from source/tests: the `PackTxWord` comment
   contradicts its low-byte-first implementation and must be corrected from
   verified behavior.

Acceptance: distinguish existing failures from migration failures and retain
commands, configurations and results for comparison.

## 2. Migrate memory and make frame validity explicit

Primary files: `src/EthernetFrameIo.lvt`, `tests/EthernetFrameIoTest.lvt`.

1. Initially instantiate `Ram<byte, 2048>` explicitly for both buffers and
   replace `ReadByte`/`WriteByte` with `Read`/`Write`. Keep public methods and
   constructor compatible; make byte/vector conversions explicit where needed.
   Use Auto storage intent initially; choose Block or Distributed only with
   evidence and a documented resource requirement.
2. Keep scheduled access for this first migration. Check call completion and
   state transitions against the new latency; do not substitute a synchronous
   port into code expecting scheduled methods.
3. Define write-before-read ownership: callers finish writing every byte in the
   declared TX range before submission and do not modify a submitted frame.
   RX becomes available only after capture completes. Define invalid-index and
   unavailable-frame behavior consistently for RAM-backed and injected RX.
   Audit injected RX callers for complete initialization of the exposed prefix.
4. Zero unused lanes of the last AXI TX word directly, without reading beyond
   `txLength`. This is bus-word padding; keep Ethernet minimum-frame padding a
   separately documented responsibility. Do not clear whole RAM arrays.
5. Reject invalid TX lengths before submission and device access, with observable
   failure in an additive checked API if the existing void method cannot report
   it. Do not silently clamp word count while publishing a different length.
   Derive the maximum from the EthernetLite data/register boundary, not RAM depth.
6. Reset validity, ownership and pending-operation metadata; never expose retained
   bytes as a new frame. Specify behavior for reset during RAM or AXI transactions
   and whether the attached slave shares reset.

Acceptance: no legacy RAM references; current public call sites compile;
deterministic partial-word output; no unwritten payload consumed under the
documented contract; invalid frames cannot reach device control registers.

## 3. Add behavioral and timing coverage

- Test RX ping and pong payload capture, byte order, complete-frame publication,
  control acknowledgement, consumption and subsequent frames.
- Test TX payloads of lengths 1, 2, 3, 4, 5, representative packet lengths and
  the supported maximum; include high-bit bytes and long-then-short reuse.
- Test negative/zero/oversized lengths, boundary indices and repeated submission
  according to the chosen checked API contract.
- Vary AXI address/data acceptance independently and stall responses. Verify
  request stability and exactly one transfer per accepted request.
- Test reset during activity, retained storage with invalid metadata, and fresh
  transfers after reset. Test the supported overlap of application calls and
  background processing; explicitly reject or document unsupported overlap.
- Use bounded handshake-driven tests. Scheduled getter calls themselves cost
  cycles, so use a native HDL harness where exact edge timing matters.
- Run the full Livt.Net suite in debug/release; exercise the memory/AXI tests
  with normal optimizations and `-O none`. Publish measured completion latency
  and sustained transfer rate under stated stalls, rather than importing the
  standalone RAM's measured cycle counts as a Net guarantee.

Acceptance: all baseline tests and new transfer regressions pass; inspected HDL
has the intended storage, no whole-array reset/copy and no unintended extra port.
Synthesis/resource and timing claims require actual target-tool measurements.

## 4. Introduce compile-time frame configuration

After the compatibility migration passes:

1. Add defaulted value parameters to frame-consuming helpers, for example
   `EthernetFrameParser<FRAME_CAPACITY: int = 64>` and
   `Ipv4PacketParser<FRAME_CAPACITY: int = 128>`, using
   `byte[FRAME_CAPACITY]` consistently through child parsers, recognizers,
   responders and composers. Preserve the current defaults.
2. Add static assertions for each helper's greatest required offset. Buffer
   capacity does not establish received packet length: introduce explicit valid
   length checks where truncated input can reach protocol classification.
3. Make frame-I/O RX capacity and TX storage capacity explicit compile-time
   parameters with current behavior as defaults. Derive loop bounds and array
   dimensions from them; constrain RX word alignment and both capacities to
   supported EthernetLite geometry. Keep storage capacity, captured prefix and
   maximum transmittable length distinct. Initially retain the 2048-byte storage
   default; right-size RX to 128 bytes only as a measured follow-up.
4. Test defaults and at least two nondefault sizes, invalid configurations, and
   multiple differently configured instances in one design. Confirm that
   configuration introduces no runtime selection logic.

Keep generic payload types out of protocol APIs. Backend type injection is useful
only if a concrete second backend is needed; generic RAM already supplies the
necessary first-stage reuse. Avoid introducing inherited/public nested interface
facades while compiler issues #486–#488 remain open. Existing direct interfaces
and private storage composition avoid expanding into those known failure paths.

## 5. Evaluate a hardware-level transfer core separately

Four scheduled byte accesses per AXI word may dominate frame throughput. Measure
first. If it misses the application's budget, prototype an explicitly wired
`SynchronousRam` transfer core with a single command owner, then compare latency,
throughput, resources and timing against stage 2. A 32-bit store also requires
explicit assembly or read-modify-write for byte APIs: do not assume byte masks
exist in the new RAM contract.

Retain a convenient scheduled frame API over any improved core. Defer streaming,
UDP, IPv4/TCP options and a generic AXI-library extraction to independent work.

## 6. Integrate and document the release

- Update README, usage and hardware/design notes with dependency versions,
  generic examples, bounds, write-before-read, reset, concurrency and timing
  contracts. Remove obsolete HDL-copy guidance and repair the frame flow example.
- Choose a new Livt.Net development version before publication; do not publish
  changed dependency/behavior under the existing 1.0.1 identity. Document any
  checked API and capacity changes explicitly.
- Validate dependent applications using isolated dependency snapshots. The
  sibling `livt-web-app` uses `EthernetFrameIo` but currently pins Livt.Net
  0.26.0, so its ordinary build would not verify this source migration.
- Keep reusable integration verification in the sibling `livt` project, compiler
  reproductions in `livt-gen-vhdl-verification`, and evidence links in
  `livt-project`, following its regression-ownership policy.

Suggested review units: (1) baseline plus RAM/validity migration and regressions,
(2) compile-time capacities plus configuration tests, (3) consumer integration
and release documentation. Performance-core work has a separate measurement gate.
