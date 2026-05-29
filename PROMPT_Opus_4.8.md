0a. Study `docs/*` to learn research and the specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study the rest of the repo, the application source code is in `src/*`.

## Plan Instructions

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and study existing source code in `src/*` and compare it against `docs/specs/*`. Analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented. Ultrathink. Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete.
2. Analyse what changes so far (from the plan) are working, what are not. Evaluate all the options, and determine feasible opitons to move forward, and update @IMPLEMENTATION_PLAN.md accordingly

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Treat `scripts/*` as the project's standard library for shared utilities and components. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

ULTIMATE GOAL: We want to achieve [Make `./scripts/bench.sh` self-hosted run (`./scripts/selfhosted_interpreter.sh src/sample.s`, stdin=`hi`) at least 10× faster.]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at specs/FILENAME.md. If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md.

---

## Implemenat Instructions
1. Your task is to implement functionality per the specifications. Follow @IMPLEMENTATION_PLAN.md and choose the most important item to address. Before making changes, search the codebase (don't assume not implemented).
2. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Ultrathink.
3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings. When resolved, update and remove the item.
4. When the tests pass, update @IMPLEMENTATION_PLAN.md, then `git add -A` then `git commit` with a message describing the changes. After the commit, `git push`.
5.  Important: When authoring documentation, capture the why — tests and implementation importance.
6.  Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
7.  As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1  if 0.0.0 does not exist.
8.  You may add extra logging if required to debug issues.
9.  Keep @IMPLEMENTATION_PLAN.md current with learnings — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
10. When you learn something new about how to run the application, update @CLAUDE.md but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
11. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md even if it is unrelated to the current piece of work.
12. Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
13. When @IMPLEMENTATION_PLAN.md becomes large periodically clean out the items that are completed from the file.
14. If you find inconsistencies in the specs/* then use an Opus 4.6 with 'ultrathink' requested to update the specs.
15. IMPORTANT: Keep @CLAUDE.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.md`. A bloated CLAUDE.md pollutes every future loop's context.