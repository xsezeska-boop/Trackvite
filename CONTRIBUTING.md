# Contributing to Trackvite

Bug reports and pull requests are welcome. Trackvite is source-available under the **PolyForm Noncommercial License 1.0.0**, not MIT or GPL. Read [LICENSE](LICENSE) and [NOTICE](NOTICE) before using or changing the code. Commercial use is not granted by this license.

## Propose a change

1. Open an issue describing the problem or feature. For larger changes, discuss the approach first.
2. Fork this repository and create a focused branch.
3. Make your change and add meaningful regression checks where needed.
4. Build on macOS 14 or later using `bash scripts/build.sh`. See the README for signing and permission limitations.
5. Open a pull request with the problem, resulting behavior and validation performed.

Never commit credentials, signing keys, local activity data, build caches or app bundles. Redact private app/window titles and website addresses in screenshots and logs. Permission tests must not silently grant access or bypass macOS security controls.

## Checks

Checks live in `Tests/` and are standalone Swift programs rather than XCTest targets. For example:

```sh
swiftc Sources/Tracker/ScreenTimeBudget.swift Tests/ScreenTimeBudgetChecks.swift -o /tmp/trackvite-budget-checks
/tmp/trackvite-budget-checks
```

Integration checks use app sources excluding `TrackerApp.swift`. Saved-state checks use temporary files; browser script checks must not close real user tabs.

## Contribution terms

Submit only code you have the right to contribute. Contributions are provided under the same PolyForm Noncommercial License 1.0.0. Contributors retain their copyright; submission does not transfer ownership or grant the maintainer additional commercial relicensing rights. Any different terms require a separate agreement.
