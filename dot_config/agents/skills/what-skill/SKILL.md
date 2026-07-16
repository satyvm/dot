---
name: what-skill
description: Ask which skill or flow fits your situation. A router over all available skills.
disable-model-invocation: true
---

# What Skill

You don't remember every skill, so ask. This is the central directory and router for all 33 skills configured in this environment.

---

## 1. Skill Flows & Pipelines

Most of your engineering and writing tasks run along structured paths. Use the categories below to identify the flow you need.

### The Main Engineering Flow: Idea → Ship
The standard route for building features or refactoring a codebase:
1. **`/grill-with-docs`** — Relentless design/plan interview to align on ideas. Stateful: updates `CONTEXT.md` and ADRs.
2. **`to-spec`** — Synthesize the conversation context into a spec/PRD and publish to the issue tracker.
3. **`to-tickets`** — Break the spec/plan into vertical tracer-bullet tickets with blocking links.
4. **`implement`** — Write code for a ticket or spec. Drives `/tdd` internally, runs typechecking and tests, runs `/code-review`, and commits.
5. **`/tdd`** — Red-green-refactor loop to build specific behaviors test-first.
6. **`/code-review`** — Two-axis review of a branch/PR diff against local coding standards and the spec/PRD.

### On-Ramps
Starting situations that feed into the main engineering flow:
*   **Bugs or external feature requests piling up** → **`triage`**: Move issues/PRs through a state machine to create agent-ready briefs.
*   **Obscure bug, flakiness, or regression** → **`diagnose`** (diagnosing-bugs): Find a single command/test that reproduces the bug, then fix it test-first.
*   **Massive, foggy, or greenfield effort** → **`wayfinder`**: Chart a shared map of investigation issues on the tracker to produce decisions rather than deliverables until the path is clear.

---

## 2. Complete Directory of All 33 Skills

Below is the exhaustive list of all 33 skills, grouped by category.

### 💻 Core Engineering & TDD
*   **`implement`**
    *   *Path:* `skills/implement`
    *   *Summary:* Implement feature work based on a spec or set of tickets.
    *   *When to Use:* When you have a ticket or spec ready and want to write, test, and commit the code.
*   **`tdd`**
    *   *Path:* `skills/tdd`
    *   *Summary:* Drive test-driven development (red-green-refactor loop) for concrete behaviors.
    *   *When to Use:* When you want to build features or fix bugs test-first, especially at pre-agreed seams.
*   **`code-review`**
    *   *Path:* `skills/code-review`
    *   *Summary:* Reviews diffs since a fixed point on two axes: local standards compliance and spec compliance.
    *   *When to Use:* Before merging/committing an implementation or PR to verify correctness.
*   **`resolving-merge-conflicts`**
    *   *Path:* `skills/resolving-merge-conflicts`
    *   *Summary:* Step-by-step guidance to safely resolve git merge or rebase conflicts.
    *   *When to Use:* When a git operation halts due to merge conflicts that require manual resolution.

### 📐 Architecture & Design Systems
*   **`grill-with-docs`**
    *   *Path:* `skills/grill-with-docs`
    *   *Summary:* Relentless stateful plan/design interview that updates `CONTEXT.md` and records ADRs.
    *   *When to Use:* To align on a design and preserve decisions statefully in the repository.
*   **`improve-codebase-architecture`**
    *   *Path:* `skills/improve-codebase-architecture`
    *   *Summary:* Scans the codebase for shallow modules, generates a deepening report, and refactors them.
    *   *When to Use:* During downtime to improve codebase testability, module depth, and AI-navigability.
*   **`codebase-design`**
    *   *Path:* `skills/codebase-design`
    *   *Summary:* A shared vocabulary reference (module, depth, seam, adapter) for module design.
    *   *When to Use:* Internal reference for other skills or when explicitly designing a module's shape.
*   **`domain-modeling`**
    *   *Path:* `skills/domain-modeling`
    *   *Summary:* Sharpens domain terminology (ubiquitous language) and records hard-to-reverse ADRs.
    *   *When to Use:* When defining fuzzy domain terms or recording major architectural decisions.
*   **`frontend-design`**
    *   *Path:* `skills/frontend-design`
    *   *Summary:* Rules for rich aesthetics, premium color systems, modern typography, and micro-animations.
    *   *When to Use:* Designing new UI or reshaping existing views to feel premium and custom-designed.
*   **`vercel-react-best-practices`**
    *   *Path:* `skills/vercel-react-best-practices`
    *   *Summary:* Next.js and React performance optimization guidelines from Vercel.
    *   *When to Use:* Writing/reviewing React components, caching, data fetching, or optimizing bundles.
*   **`web-design-guidelines`**
    *   *Path:* `skills/web-design-guidelines`
    *   *Summary:* Audits web pages for accessibility (WCAG), layout consistency, and UX guidelines.
    *   *When to Use:* When asked to "review my UI", audit design consistency, or verify accessibility.

### 📋 Planning & Tracking
*   **`to-spec`**
    *   *Path:* `skills/to-spec`
    *   *Summary:* Synthesize conversation and codebase state into a spec (PRD) on the issue tracker.
    *   *When to Use:* To generate a PRD from previous chat history without further interviewing.
*   **`to-tickets`**
    *   *Path:* `skills/to-tickets`
    *   *Summary:* Break down a plan/spec into vertical tracer-bullet tickets with blocking relationships.
    *   *When to Use:* Converting a spec or roadmap into a local `tickets.md` checklist or tracker issues.
*   **`triage`**
    *   *Path:* `skills/triage`
    *   *Summary:* Process raw incoming bugs/feature requests through a state machine of triage roles.
    *   *When to Use:* Refining external reports/PRs into clean, actionable briefs for developers.
*   **`wayfinder`**
    *   *Path:* `skills/wayfinder`
    *   *Summary:* Map out huge, multi-session efforts on the tracker to produce decisions and push back fog.
    *   *When to Use:* Launching massive, complex, or highly uncertain initiatives that require sequential discovery.

### ✍️ Writing & Content Creation
*   **`writing-beats`**
    *   *Path:* `skills/writing-beats`
    *   *Summary:* Exploitative writing tool that builds an article beat-by-beat, grounding concepts progressively.
    *   *When to Use:* Interactively writing a structured article or documentation from a pile of raw ideas.
*   **`writing-fragments`**
    *   *Path:* `skills/writing-fragments`
    *   *Summary:* Exploratory brain-dump tool to collect raw thoughts and fragments from the user.
    *   *When to Use:* Initial brainstorming phase to save unstructured thoughts to a markdown file.
*   **`writing-shape`**
    *   *Path:* `skills/writing-shape`
    *   *Summary:* Shapes unstructured fragments or transcripts into a clean article paragraph-by-paragraph.
    *   *When to Use:* Formatting raw material into a structured draft with deliberate paragraph formats.
*   **`edit-article`**
    *   *Path:* `skills/edit-article`
    *   *Summary:* Restructures, clarifies, and tightens draft prose, enforcing a 240-character paragraph limit.
    *   *When to Use:* Polishing and editing draft articles to optimize flow and formatting.

### 🔧 Tooling & Script Automation
*   **`wizard`**
    *   *Path:* `skills/wizard`
    *   *Summary:* Generates interactive bash scripts to walk humans through tedious manual procedures.
    *   *When to Use:* Creating setup, migration, or deployment scripts that open URLs and write secrets safely.
*   **`setup-pre-commit`**
    *   *Path:* `skills/setup-pre-commit`
    *   *Summary:* Configures Husky, lint-staged, Prettier, and Jest in the repository.
    *   *When to Use:* Setting up automated commit-time validation in a new repository.
*   **`skill-creator`**
    *   *Path:* `skills/skill-creator`
    *   *Summary:* Automates the creation, modification, refinement, and evaluation of agent skills.
    *   *When to Use:* When you want to author a new skill from scratch, optimize a skill's description for triggering accuracy, or run evals/benchmarks on skill performance.
*   **`git-guardrails-claude-code`**
    *   *Path:* `skills/git-guardrails-claude-code`
    *   *Summary:* Sets up Claude Code hooks to intercept and block destructive git commands.
    *   *When to Use:* Securing a repository against accidental hard resets, cleans, or force pushes.
*   **`migrate-to-shoehorn`**
    *   *Path:* `skills/migrate-to-shoehorn`
    *   *Summary:* Migrates TypeScript test files from unsafe `as` type casts to `@total-typescript/shoehorn`.
    *   *When to Use:* Refactoring test mock data casting for safer type coverage.

### 📂 Knowledge & Workspace Management
*   **`obsidian-vault`**
    *   *Path:* `skills/obsidian-vault`
    *   *Summary:* Search, create, and link notes inside an Obsidian vault.
    *   *When to Use:* Managing a local personal knowledge base with wikilinks and index files.
*   **`loop-me`**
    *   *Path:* `skills/loop-me`
    *   *Summary:* Stateful plan interview to specify recurring workflows and save them to `workflows/*.md`.
    *   *When to Use:* Designing automated loops or repeated tasks with triggers and checkpoints.
*   **`scaffold-exercises`**
    *   *Path:* `skills/scaffold-exercises`
    *   *Summary:* Scaffolds educational programming exercises with sections, problems, and solutions.
    *   *When to Use:* Creating coursework, workshop problems, or exercise stubs that pass linting.

### 🧠 Standalone & Utilities
*   **`grill-me`**
    *   *Path:* `skills/grill-me`
    *   *Summary:* Relentless stateless plan interview to stress-test designs without saving local files.
    *   *When to Use:* Sharpening or stress-testing a plan that does not live inside a git repository.
*   **`grilling`**
    *   *Path:* `skills/grilling`
    *   *Summary:* Relentless questioning primitive used to challenge plan assumptions.
    *   *When to Use:* Internal primitive called by `/grill-me` and `/grill-with-docs`.
*   **`prototype`**
    *   *Path:* `skills/prototype`
    *   *Summary:* Builds a small throwaway script to test out state modeling or UI design ideas.
    *   *When to Use:* When design questions are hard to settle on paper and require quick experimentation.
*   **`research`**
    *   *Path:* `skills/research`
    *   *Summary:* Spawns a background agent to investigate questions against high-trust primary sources.
    *   *When to Use:* Gathering facts, documentation, or API specs in a cited markdown file asynchronously.
*   **`handoff`**
    *   *Path:* `skills/handoff`
    *   *Summary:* Compacts the current session context into a markdown file in the OS temp directory.
    *   *When to Use:* Forking sessions or crossing context boundaries when the context window is full.
*   **`claude-handoff`**
    *   *Path:* `skills/claude-handoff`
    *   *Summary:* Compiles a handoff summary and immediately launches a background agent.
    *   *When to Use:* Delegating tasks to run asynchronously in a background agent.
*   **`writing-great-skills`**
    *   *Path:* `skills/writing-great-skills`
    *   *Summary:* Reference guide for writing predictable, high-quality agent skills.
    *   *When to Use:* When authoring or refactoring skills in the `.agents` or config directory.
