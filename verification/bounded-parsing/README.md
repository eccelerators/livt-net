# Bounded parsing promotion

The bounded parsing implementation was promoted to the normal Livt.Net sources
and tests on 2026-09-23 after the nested borrowed-read compiler fix. The duplicate
standalone sources and migration patches have been removed.

See `docs/packet-parsing.md` in the package root for the provider-bound API,
structural parse results, supported formats and ownership rules. Run the normal
package suite with `livt test -f` from the repository root.

Verification used Livt tests only: the unprimed draft passed 14/14, Net 93/93,
Web 36/36 and WebApp 16/16. The two responder suites passed 7/7 again with
stronger assertions for source release/reuse and wrong ARP EtherType. The
canonical nested borrowed-read compiler regression passed 5/5.

No synthesis, native HDL harness, bitstream, flash or board test was run.
