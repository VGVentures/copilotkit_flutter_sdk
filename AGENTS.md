# Agent instructions

These instructions apply to every agent that changes this repository.

## Before you change code

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). It holds the packages
and their layers, the layout of each package, and the conventions for code,
tests and doc comments. Keep every change inside those rules. When a change
needs to break one, follow
[Following the architecture](docs/ARCHITECTURE.md#following-the-architecture):
update the document in the same pull request instead of working around it.

For the setup, the checks CI runs, and the commit and pull request workflow,
see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Before you finish

Run the checks in
[`CONTRIBUTING.md`](CONTRIBUTING.md#step-5-run-the-checks) and fix what
they report. Write commits and pull request titles as that guide describes,
and ship multi-step work as a stack of small pull requests.
