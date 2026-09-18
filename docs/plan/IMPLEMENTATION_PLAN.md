# Implementation Plan

1. Bootstrap Flutter inside the workspace and generate Android/iOS scaffold.
2. Write failing unit tests for lock state, unlock verification, authenticated-encryption behavior, settings, and panic evaluation.
3. Implement minimal core services until unit tests pass.
4. Write failing widget tests for locked cover, unlock, background auto-lock, panic conceal, and route gating.
5. Implement the two cover tools, secret shell, and lifecycle gating.
6. Add encrypted vault repository and import/export boundaries with tests.
7. Add browser profile model and download-to-vault boundary with documented platform limitations.
8. Add panic sensor adapter and native privacy/disguise bridges.
9. Add CI for format/analyze/test, Android build, iOS no-codesign build, CodeQL, and dependency review.
10. Run fresh verification, inspect for secret leakage, commit coherent slices, create the private GitHub repository, push, then hand to independent REVIEW/TEST.
