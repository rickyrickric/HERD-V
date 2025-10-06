## Summary

Short description of the change and why it is needed.

This PR upgrades the `csv` package to `^6.0.0` and runs validation (analyzer, tests, web build).

## Changes

- Bumped dependency: `csv: ^6.0.0` (in `pubspec.yaml`).

## Validation

- Ran `flutter analyze` — only non-blocking warnings remain.
- Ran `flutter test` — all tests passed.
- Built `flutter build web --release` — web build succeeded and produced `build/web`.

## Checklist

- [ ] Code changes are covered by unit tests where applicable
- [x] Local `flutter analyze` passed (warnings only)
- [x] Local `flutter test` passed
- [x] Local `flutter build web --release` succeeded
- [ ] PR description is clear and linked to relevant issues

## Notes

No code changes were necessary for the upgrade — existing CSV usage appears compatible with 6.0.0.

If the project CI/other platforms show failures, address them in follow-up commits on this branch.
