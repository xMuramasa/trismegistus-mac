# Protocol copy

`schema.json` and `examples/` are copied from `xMuramasa/trismegistus` (`protocol/`, commit `e17cdf3`). That repo
owns the protocol; this copy exists so the Swift package's contract tests run without a checkout of the other repo.
`scripts/sync-protocol.sh` refreshes it and a test fails when the two differ in sha256.

`terminal.schema.json`: the `/api/terminal` messages (the Mac app's terminal drawer, trismegistus#31), copied by hand from
trismegistus a1d8b53. `scripts/sync-protocol.sh` doesn't copy it and `SOURCE` doesn't hash it yet; #64 adds both.
