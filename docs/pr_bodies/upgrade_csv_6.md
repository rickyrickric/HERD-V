Upgrade csv to 6.0.0

This PR upgrades the `csv` package to `^6.0.0`.

Validation performed locally:

- `flutter analyze` — warnings only
- `flutter test` — all tests passed
- `flutter build web --release` — build succeeded

Potential follow-ups:
- Run CI and address any platform-specific failures
- If other packages need bumping, handle in separate PRs

Checklist

- [x] Bump `csv` in `pubspec.yaml`
- [x] Local analysis/tests/build
- [ ] Open PR and run CI
