param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '1.6.1',
    [string]$GoExecutable = 'go',
    [string]$NpmExecutable = 'npm.cmd'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE): $($Arguments -join ' ')" }
}
$revision = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'A Git checkout is required.' }
if (& git -C $root status --porcelain) { throw 'Commit source changes before building a release.' }
$env:GOTOOLCHAIN = 'local'
$env:GOWORK = 'off'
$env:CGO_ENABLED = '0'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:GOAMD64 = 'v1'
if ((& $GoExecutable env GOVERSION) -ne 'go1.27.1') { throw 'Use Go 1.27.1 for reproducible release binaries.' }
$output = Join-Path $root "dist/windows-v$Version"
if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
$name = "sshpiperd-windows-x64-v$Version"
$stage = Join-Path $output $name
[void][IO.Directory]::CreateDirectory((Join-Path $stage 'plugins'))
$web = Join-Path $root 'cmd/sshpiperd-webadmin/internal/httpapi/web'
Invoke-Checked $NpmExecutable @('--prefix', $web, 'ci', '--no-audit', '--no-fund')
Invoke-Checked $NpmExecutable @('--prefix', $web, 'run', 'build')
$flags = '-s -w -X main.mainver=' + $Version
Invoke-Checked $GoExecutable @('-C', (Join-Path $root 'cmd/sshpiperd'), 'build', '-mod=readonly', '-trimpath', '-buildvcs=true', '-ldflags', $flags, '-o', (Join-Path $stage 'sshpiperd.exe'), '.')
foreach ($command in @('sshpiperd-admin', 'sshpiperd-webadmin')) {
    Invoke-Checked $GoExecutable @('-C', $root, 'build', '-mod=readonly', '-tags', 'full', '-trimpath', '-buildvcs=true', '-ldflags', $flags, '-o', (Join-Path $stage "$command.exe"), "./cmd/$command")
}
foreach ($plugin in @('workingdir', 'yaml', 'fixed', 'revtunnel', 'failtoban', 'username-router', 'lua', 'metrics')) {
    Invoke-Checked $GoExecutable @('-C', $root, 'build', '-mod=readonly', '-tags', 'full', '-trimpath', '-buildvcs=true', '-ldflags', '-s -w', '-o', (Join-Path $stage "plugins/$plugin.exe"), "./plugin/$plugin")
}
foreach ($file in @('README.md', 'LICENSE', 'FORK-NOTES.md', 'RELEASE-WINDOWS.md')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
}
$utf8 = New-Object Text.UTF8Encoding($false)
$provenance = [ordered]@{ version = $Version; repository = 'https://github.com/wadaxiyang/sshpiper'; commit = $revision; go = '1.27.1'; target = 'windows/amd64'; crypto = 'v0.0.0-20261021065834-e58e5f25157c' }
[IO.File]::WriteAllText((Join-Path $stage 'BUILD.json'), ($provenance | ConvertTo-Json) + "`n", $utf8)
$manifest = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($stage.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
[IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.json'), (ConvertTo-Json -InputObject $manifest) + "`n", $utf8)
if (& git -C $root status --porcelain) { throw 'Build changed tracked source files.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $output "$name.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($zip + '.sha256', "$hash  $name.zip`n", [Text.Encoding]::ASCII)
Invoke-Checked (Join-Path $stage 'sshpiperd.exe') @('--version')
Write-Host "Release ZIP: $zip"
