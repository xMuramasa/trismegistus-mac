# trismegistus-mac

A macOS menu bar companion for Hermes Agent. It talks to the Trismegistus relay (`xMuramasa/trismegistus`) over the
same WebSocket protocol as the Android app: replies, live tool progress and approvals, from the menu bar.

Status: spec. Nothing builds yet. See `SPEC.md`.

Layout (planned):

- `TrismegistusKit/`: a Swift package with the protocol types (generated from `protocol/schema.json`), the relay
  client, reconnect/replay logic and the state model. Pure Swift, no UI, tested against `protocol/examples/`.
- `App/`: the SwiftUI menu bar app (Xcode project). Depends on `TrismegistusKit`.
- `protocol/`: a copy of the protocol owned by the trismegistus repo (`scripts/sync-protocol.sh`).

Built on Martin's Mac over SSH from optiplex (`ssh mac`); Hermes verifies, commits and pushes.
