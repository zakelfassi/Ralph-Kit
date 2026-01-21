# Kickoff: Generate Specs/Docs with a Memory-Backed Agent

Ralph works best when `specs/` and `docs/` are **high-quality and implementation-ready**.

For brand-new projects, you often want a *different agent* than the loop runner to author these files:

- A “memory-backed” agent (ChatGPT Projects, Claude Projects, a long-running internal agent, etc.) that already knows your product domain, prior codebases, and preferences.
- Then you hand off the resulting `specs/*` + `docs/*` to Ralph (this kit) for planning/building.

This repo provides a repeatable workflow to do that.

## Recommended flow (greenfield repo)

1. Create an empty repo (or minimal scaffold).
2. Install Ralph Kit into it:
   ```bash
   /path/to/ralph-kit/install.sh /path/to/your/repo --wrapper
   ```
3. Generate a kickoff prompt you can paste into your memory-backed agent:
   ```bash
   cd /path/to/your/repo
   ./ralph/bin/kickoff.sh "<one paragraph project brief>"
   ```
   This writes `docs/KICKOFF_PROMPT.md` in the target repo.
4. Paste `docs/KICKOFF_PROMPT.md` into your memory-backed agent.
5. Apply the agent’s output (ideally as a git patch) to create:
   - `AGENTS.md` (real build/test commands)
   - `docs/*` (PRD, architecture, design notes if relevant)
   - `specs/*` (one file per topic of concern, with acceptance criteria)
   - `IMPLEMENTATION_PLAN.md` (prioritized checklist, including REQUIRED TESTS per item)
6. Run Ralph planning/building:
   ```bash
   ./ralph.sh plan 1
   ./ralph.sh build 10
   ```

## Tips

- Keep specs outcome-focused: acceptance criteria should be **WHAT to verify**, not implementation details.
- If you have a “seed” repo, attach it to the memory-backed agent (or paste key files) so it can reuse patterns.
- Don’t try to write the entire world upfront: 3–8 high-signal spec files beats 40 vague ones.
