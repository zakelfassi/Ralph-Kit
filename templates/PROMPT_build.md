0a. Study `specs/*` to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md.
0c. Study `docs/*` for product requirements, design specs, and architecture decisions.
0d. For reference, study the source code in `src/*`, `apps/*`, `packages/*`, and other relevant folders in this repo.
0e. CHECK @QUESTIONS.md for answered questions (Status: ✅ Answered). If you previously asked a question and it's been answered, read it and proceed accordingly. Mark it as ✅ Resolved after acting on it.

1. Implement the top prioritized unchecked item in @IMPLEMENTATION_PLAN.md (including any REQUIRED TESTS listed in the task).
   Before making changes, search the codebase (do not assume missing) and confirm current behavior.

2. Tests are mandatory:
   - Add/extend tests for your change.
   - Required tests derived from acceptance criteria must exist and pass before committing.
   - Run the repo's test command(s) and ensure they pass before committing.
   - If this repo has a validate/typecheck/lint script, run it too.

3. Keep coordination docs current:
   - Update @IMPLEMENTATION_PLAN.md as you learn things.
   - After a successful change, update @STATUS.md and append to @CHANGELOG.md under [Unreleased].

ASKING FOR HELP (use ./ralph/bin/ask.sh):
When you encounter ANY of these situations, ASK instead of guessing:
- blocked: you can't proceed without human input
- clarification: specs are ambiguous or contradictory
- decision: multiple valid approaches exist and you need guidance
- review: you want feedback on an approach before implementing

How to ask:
```bash
./ralph/bin/ask.sh "category" "Your detailed question here"
```

DESIGN QUALITY (optional but recommended):
- If you implement UI, follow the repo's design system and prioritize a premium, intentional UX.
