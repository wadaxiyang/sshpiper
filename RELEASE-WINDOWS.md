# SSHPiper 1.6.1 - Windows x64 fork build

This is the **wadaxiyang fork**, retaining the original SSHPiper version number.
It is built from upstream master `7e41ec681d91872fe1115189ad98121624ef73ee`
plus the fork fixes below, not from the upstream v1.6.1 tag.
The exact source commit and toolchain are included in `BUILD.json`.

- Retains the merged Windows process/job-handle repair from PR #846.
- Repairs issue #862's unused upstream connection leaks, including connections
  completed after the downstream authentication deadline (upstream PR #863 and
  sshpiper.crypto PR #5). The crypto dependency is pinned to this user's fork.
- Tests unreadable host-key handling on Windows with a real exclusive file
  handle instead of assuming Unix permission bits apply to Windows.
- Makes plugin fixtures platform-aware and file-URI conversion independent of
  the test host. Existing plugin permission checks remain fail-closed; the
  Windows routing/parsing fixtures explicitly use their existing test opt-out.
- Includes the daemon, admin CLI, embedded web dashboard, and all eight Windows
  plugins. Build: Go 1.27.1, Windows amd64, CGO disabled.

The generic ZIP does not include a deployment's Lua routing configuration or
host private key. Keep your existing configuration and key when upgrading.
Daemon, crypto, plugin, admin, and native end-to-end checks have passed; bounded
regression tests do not establish that every possible long-running timeout has
been eliminated.

SHA-256 checksums accompany the ZIP; per-file checksums are inside the archive.
To rebuild from a clean clone, install Go 1.27.1 and Node.js 24.13.1 and run:

```powershell
./scripts/build-windows.ps1 -Version 1.6.1
```

Release binaries and ZIPs are written under `dist/windows-v1.6.1/`.
The manually dispatched `Fork Windows release` workflow tests, builds, and
publishes this fork only; it does not publish upstream container images.
