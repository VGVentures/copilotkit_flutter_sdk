# Architecture decision records

One file per decision, numbered in the order they were made. A record is
never edited after it is accepted; a later record supersedes it and both say
so.

## Template

```markdown
# NNNN. Title

**Status:** Proposed | Accepted | Superseded by NNNN

## Context

What is the situation and the problem.

## Decision

What we do.

## Alternatives

What else was considered and why it was rejected.

## Consequences

What becomes easier, what becomes harder, and what follows from it.
```

## Index

| # | Title |
| --- | --- |
| [0001](0001-hybrid-feature-layout.md) | Hybrid feature layout, moved before refactoring |
| [0002](0002-agent-bloc-and-immutability.md) | `CopilotAgent` as a bloc, immutability everywhere |
| [0003](0003-nullable-copy-with-closures.md) | Nullable `copyWith` fields take getter closures |
| [0004](0004-uuid-for-ids.md) | `uuid` for run, thread, message and tool-result ids |
| [0005](0005-equatable-value-models.md) | `Equatable` on every value model |
| [0006](0006-partial-json-in-house.md) | Partial JSON parsing stays in-house |
