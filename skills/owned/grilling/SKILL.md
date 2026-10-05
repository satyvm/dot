---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview me relentlessly about every aspect of this until we reach a shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.

If a *fact* can be found by exploring the environment (filesystem, tools, etc.), look it up rather than asking me. The *decisions*, though, are mine — put each one to me and wait for my answer.

Before the first question, read `.local/CONTEXT.md` and the ADRs in `.local/adr/` if they exist. As decisions land:

- Update durable domain terms and definitions in `.local/CONTEXT.md`.
- Record accepted architectural decisions in `.local/adr/<NNNN>-<decision-slug>.md`, using the next available four-digit number. Include status, context, decision, and consequences.
- Do not create an ADR for a tentative preference or an easily reversible implementation detail.

These context updates are the only allowed side effects until I confirm we have reached a shared understanding. Do not implement the discussed work before that confirmation.
