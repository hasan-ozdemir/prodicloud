# Contributing to clagnos

`clagnos` is maintained as a pragmatic, operator-first Azure VM toolkit. Contributions are welcome, but this repository follows a contact-first model so large changes do not drift away from the current runtime, documentation, and release contract.

## Before You Start

- Read [README.md](README.md), [AGENTS.md](AGENTS.md), and [SUPPORT.md](SUPPORT.md) first.
- Review the current command surface, task-catalog model, and configuration contract before proposing a change.
- Use the GitHub issue templates for reproducible bugs and focused feature requests whenever the discussion can happen publicly.
- For large features, contract changes, new commands, or workflow shifts, open an issue or contact the maintainer before investing in a large pull request.

## Contribution Model

- Small documentation fixes, typo fixes, and narrowly scoped bug fixes are the easiest contributions to review.
- Larger code changes should start with alignment on scope, runtime impact, and documentation impact.
- Commercial usage, sponsorship, and broader licensing questions are not handled through drive-by pull requests; use the maintainer contact path described in [LICENSE](LICENSE) and [SUPPORT.md](SUPPORT.md).

## Engineering Expectations

- Keep maintained repository docs, help text, comments, and user-facing messages in English.
- Prefer extending the current architecture instead of introducing parallel patterns.
- Keep Windows and Linux operator semantics aligned unless a real platform difference requires divergence.
- Validate before mutation and avoid destructive or live Azure behavior in CI.
- Do not add compatibility shims for retired commands or config keys unless the maintainer explicitly asks for them.

## Required Change Hygiene

- Update docs and tests in the same change when the contract changes.
- Update `CHANGELOG.md` and `release-notes.md` in the same final change set for shipped behavior, docs, workflow, or configuration changes.
- Keep `.env.example` current when the committed configuration contract changes.
- Keep `docs/prompt-history.md` aligned when the delivered repo change came from a maintainer-directed prompt workflow.

## Validation

Run the non-live checks locally before opening a pull request:

```powershell
.\tests\code-quality-check.ps1
.\tests\documentation-contract-check.ps1
.\tests\clagnos-smoke-tests.ps1
.\tests\powershell-compatibility-check.ps1
```

## Pull Requests

- Keep pull requests focused and easy to review.
- Explain the operator impact, contract changes, and validation you ran.
- If the pull request claims release-readiness or live Azure confidence, include the exact live acceptance steps and outcomes.
- Note any assumptions, skipped checks, or areas that still need maintainer review.

If you are unsure whether a change fits the repo direction, ask first. That is the expected path here.
