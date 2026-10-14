# Intent: CopilotKit Flutter SDK requirements doc

Confirmed Oct 13, 2026.

- **Outcome:** Restructure the existing requirements doc into a **Product** section (leadership: summary, why, dates and gates, demo scenario options, top risks, decisions needed) and an **Engineering** section (RN architecture, parity map, P1–P3 requirements, package architecture and API sketch, technical risks, open questions for CopilotKit).
- **User:** VGV team. Leadership reads Product; the two engineers own Engineering.
- **Why now:** Phase 1 must be split and run in parallel immediately; the Oct 16 go/no-go is three days out.
- **Success:** Product stands alone for leadership; each engineer knows what they own, what they hand off, and when; no personal names, roles only.
- **Constraint:** Decisions stay as they are. Edits limited to restructuring, adding the role-based split (Engineer A: `copilotkit_core`; Engineer B: `copilotkit_flutter`, demo app, runtime) with an API contract frozen Oct 16 and fixture-driven parallel work, closing small gaps, and cutting repetition. Markdown and tables kept.
- **Out of scope:** Changing scope, phases, or decisions; code or scaffolding; recreating the two embedded diagrams (placeholders only); settling open decisions.
- **Output:** `docs/requirements.md`.

> **Note (Oct 14):** later decisions supersede parts of this intent: the core package is `copilotkit` (not `copilotkit_core`), and B builds against `mocktail` mocks instead of a fixture-driven fake. See `docs/requirements.md` and `tasks/plan.md`.
