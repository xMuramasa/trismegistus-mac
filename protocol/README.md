# Protocol copy

`schema.json` and `examples/` are copied from `xMuramasa/trismegistus` (`protocol/`, commit `5e2d2c8`). That repo
owns the protocol; this copy exists so the Swift package's contract tests run without a checkout of the other repo.
`scripts/sync-protocol.sh` refreshes it and a test fails when the two differ in sha256.
