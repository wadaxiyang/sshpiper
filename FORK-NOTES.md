# Maintained fork: authentication timeout cleanup

## Baseline and provenance

This fork merges upstream `master` at
`7e41ec681d91872fe1115189ad98121624ef73ee` (2026-10-21 checkout).
It includes the merged Windows process-handle repair, upstream PR
[846](https://github.com/tg123/sshpiper/pull/846), while preserving this fork's
existing commit history. Upstream's latest published stable release was still
v1.6.1, which predates that repair; this is a tested master-based fork, not a
new official stable release.

## Issue 862

When downstream login times out while upstream authentication is still running,
the old daemon can block forever delivering its result. The SSH library can
also retain upstream transports after failed/replaced authentication.

- Daemon cleanup comes from Re1lya's upstream
  [PR 863](https://github.com/tg123/sshpiper/pull/863), commit
  `13edcabd75e339192005d21de9a2d86cf624e31d`: buffered result channels and cleanup
  of a late successful pipe.
- The library repair and its regression tests come from Re1lya's
  [crypto PR 5](https://github.com/tg123/sshpiper.crypto/pull/5), commit
  `60ef3e03db02d4bc0057597085513810f39b3cab`. They are retained in
  [our crypto fork](https://github.com/wadaxiyang/sshpiper.crypto/commit/e58e5f25157c38d0b4e1576325e342f0110e8ee5).
- The daemon's `go.mod` pins that fork at
  `v0.0.0-20261021065834-e58e5f25157c`; `go.sum` verifies the downloaded module.
  Root-module plugins still use upstream Go crypto. No local workspace is
  required to build the repair.
- Native Windows/macOS E2E now verifies two delayed upstream authentications
  are closed after downstream timeout, then establishes a channel through the
  same daemon without a restart.

Both upstream repair PRs were unmerged when incorporated. The fix addresses a
reproduced resource leak, not every possible cause of an SSH timeout.

## Windows host-key test

Windows does not implement Unix mode `000` as an unreadable file. The unreadable
host-key test now opens the fixture with sharing denied on Windows, exercising
the real file-read error path without changing ACLs or skipping the test.
Other platforms retain a permission-bit test, skipping only when the current
user can actually bypass those permissions (for example, root).

## Rebuilding and testing

Use Go 1.27.x. The daemon is a separate module:

```sh
cd cmd/sshpiperd
go test -count=1 -timeout 5m ./...
go test -count=1 -timeout 5m golang.org/x/crypto/ssh/...
go build -trimpath -o ../../out/sshpiperd .
```

For Windows, use `../../out/sshpiperd.exe` as the output name. Set
`CGO_ENABLED=0` for release builds. A normal clone resolves the pinned dependency
from GitHub, without any files from the developer's build directory.

The root and daemon test/lint workflows remain enabled. Windows daemon tests
now also run in CI. Native E2E uses `e2e/windows/run.ps1` or `e2e/macos/run.sh`;
the new regression is named `authentication-timeout-cleanup`.

This source fork does not replace any SSHPiperTray dependency snapshot,
deployment script, plugin binary, or existing host key by itself.
