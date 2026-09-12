---
name: merge-upstream
description: Merge upstream into the fork — element-x-ios from element-hq/develop, matrix-rust-sdk from matrix-org/main. Covers conflict playbook, regenerating generated files, rebuilding the SDK xcframework, verify pipeline, snapshot re-record, LFS push. Use when user want "merge upstream", "update from upstream", "sync with develop", "catch up with upstream".
---

# Merge upstream

Two repos, merged together. SDK first — app build against it.

## Remotes — get this right

| Repo | Upstream is | Branch | Push fork to |
|---|---|---|---|
| `element-x-ios` | `upstream` | `develop` | `origin` (evan1ee) |
| `../matrix-rust-sdk` | **`origin`** | `main` | **`fork`** (evan1ee) |

SDK's `origin` = matrix-org, real upstream. `git push origin` there aim at upstream project. Always `fork`.

## Order

1. SDK merge + `cargo check`
2. App merge + conflicts
3. Rebuild xcframework (~18 min)
4. Build, test, snapshots
5. Push (LFS first)

## 1. SDK

Fork = `main` + one commit (`Timeline::send_sticker`, `bindings/matrix-sdk-ffi/src/timeline/mod.rs`). README say so. Usually merge clean.

```bash
cd ../matrix-rust-sdk
git fetch origin --prune
git checkout -b merge-upstream-<YYYY-MM-DD>
git merge origin/main --no-edit
cargo check -p matrix-sdk-ffi --all-targets   # ~2.5 min
```

Confirm `send_sticker` survive. App's `project.yml` build against this local path (not the released package) because of it.

## 2. App merge

```bash
git fetch upstream --prune
git checkout -b merge-upstream-<YYYY-MM-DD>
git merge upstream/develop --no-edit
git diff --name-only --diff-filter=U      # full conflict list
```

### Conflict playbook

**Generated files — never hand-merge. Take either side, regenerate.**

| File | Regenerate with |
|---|---|
| `ElementX.xcodeproj/project.pbxproj` | `xcodegen` |
| `ElementX/Sources/Mocks/Generated/GeneratedMocks.swift` | `sourcery --config Tools/Sourcery/AutoMockableConfig.yml` |
| `Components/SDKMocks/Sources/Generated/SDKGeneratedMocks.swift` | `swift run tools generate-sdk-mocks local` |
| `ElementX/Sources/Generated/*` | `swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml` |
| `Package.resolved` | take theirs, let SPM resolve |

**Snapshots (`PreviewTests/Sources/__Snapshots__`)** — `git checkout --ours`, re-record in step 4. Never hand-pick LFS pointers.

**Source conflicts — read fork intent before choosing.**

Conflict HEAD side is *fork branch*, not *fork change*. Merge-base content sit on that side too, so upstream's own code that upstream later deleted look like it belong to fork. Always ask what fork actually did:

```bash
MB=$(git merge-base HEAD MERGE_HEAD)
git diff $MB HEAD -- <file>          # what fork changed
git diff $MB upstream/develop -- <file>   # what upstream changed
```

Seen both ways last time:
- `userStatusEnabled` looked fork-owned, was upstream's flag upstream then retired → drop it.
- `globalSearchEnabled` looked upstream-new, fork had **deliberately deleted** it (own search tab) → keep deleted.

**File deleted upstream, modified by fork** — find where logic move, port fork's bit there. Last time `AuthenticationClientFactory` fold into `Services/Client/ClientFactory.swift`; fork's `.withSearchIndexStore` move into `makeAuthenticationClient`.

### After conflicts

```bash
swiftlint            # errors fail build phase
swiftformat .        # run from root only
```

`type_body_length` drift common: upstream grow a class near the 1000 limit, fork's additions push over. Move fork's self-contained pieces into extension; if still over, use `// swiftlint:disable:next type_body_length` like `RoomFlowCoordinator` already do.

Dangling refs check — cheap, catches retired flags:

```bash
grep -rn "<removed symbol>" --include='*.swift' ElementX UnitTests UITests
```

## 3. Rebuild xcframework

Committed one is stale whenever SDK move. App build against `bindings/apple/generated/` (gitignored).

```bash
cd ../matrix-rust-sdk
cargo xtask swift build-framework --target aarch64-apple-ios --target aarch64-apple-ios-sim
```

~18 min. Only these two slices — match what xcframework already carry.

## 4. Verify

Resolve destination id first — bare `name:` specifier sometimes not match:

```bash
xcodebuild -showdestinations -project ElementX.xcodeproj -scheme UnitTests | grep "iPhone 17"
```

```bash
xcodebuild build -project ElementX.xcodeproj -scheme ElementX \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'id=<UUID>'
```

Pipe through `grep -E "error:|BUILD (SUCCEEDED|FAILED)|Test run with"` — raw log huge, and in-test `ERROR` log lines are expected noise (tests exercise failure paths), not failures.

### Snapshots

Suite demand **iPhone SE (3rd generation), iOS 26.5** — `PreviewTests.swift` `simulatorDevice` + `requiredOSVersion`. Wrong device = every test fail.

Recording: `RECORD_FAILURES` sit in `PreviewTests/SupportingFiles/PreviewTests.xctestplan` as `"enabled": false`. Plan entry **override** env var, so `TEST_RUNNER_RECORD_FAILURES=true` do nothing. Flip the plan:

```bash
# drop the "enabled" : false line from the RECORD_FAILURES entry, then
xcodebuild test -project ElementX.xcodeproj -scheme PreviewTests -destination 'id=<SE UUID>'
git checkout -- PreviewTests/SupportingFiles/PreviewTests.xctestplan   # revert, always
xcodebuild test -project ElementX.xcodeproj -scheme PreviewTests -destination 'id=<SE UUID>'  # verify green
```

Record run always report FAILED — that how it write. Verify run must pass.

## 5. Push

LFS objects go first or pre-receive hook reject the push:

```bash
git lfs push --all origin <branch>    # slow, GBs
git push -u origin <branch>
cd ../matrix-rust-sdk && git push -u fork <branch>
```

## Traps

- **Never `rm -rf` the whole `DerivedData/ElementX-*`.** Take `SourcePackages` with it → full re-clone of every package, slow on bad network. Stale module errors (`MLNMapOptions.h has been modified since the module file was built`) after upstream move a package: delete `DerivedData/ModuleCache.noindex` only.
- **`Components/Secrets/Secrets.swift` carry `assume-unchanged`** (`git ls-files -v` → `h`). Real keys live there, invisible to `git status`. Merge won't show it, but confirm it survive a path move. See [[secrets-regeneration]] before regenerating — must set *every* env var.
- **SDK drift.** Local SDK run ahead of the components version upstream pin. App code usually fine; `SDKGeneratedMocks.swift` break first (`method does not override any method from its superclass`). Regenerate, don't hand-edit.
- **Fork param added to a helper upstream rework** → test-only compile error. Add the fork's argument, don't drop it.
