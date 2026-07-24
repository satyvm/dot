---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Before editing code, read `AGENTS.md`, `.local/CONTEXT.md`, and relevant records in `.local/adr/` when they exist. Use the glossary's domain vocabulary and preserve the boundaries established by accepted ADRs. If the requested spec or ticket conflicts with an ADR, stop and surface the conflict instead of silently overriding it.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch.
