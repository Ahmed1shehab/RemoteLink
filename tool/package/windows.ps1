<#
.SYNOPSIS
  Builds a signed Windows installer for the Remote Link desktop companion.

.DESCRIPTION
  Run from anywhere in the checkout:

      pwsh tool/package/windows.ps1

  Configuration comes from the environment, so no certificate detail is ever
  checked in:

      RL_SIGN_THUMBPRINT  SHA-1 thumbprint of the code-signing certificate in
                          the current user's store. List candidates with:
                            Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
      RL_TIMESTAMP_URL    RFC 3161 timestamp server. Defaults to DigiCert's.

  Both optional. Without a thumbprint this produces an unsigned installer and
  says what SmartScreen will do with it, which is what a contributor without a
  certificate needs.

  Signing matters more than the warning it removes: an unsigned installer that
  writes a `Run` key and opens a listening socket is the exact shape of thing
  every endpoint protection product is built to quarantine.

.NOTES
  Never run on this project's own machine — it is macOS. Written from the
  documented behaviour of signtool, ISCC and netsh; the first person to run it
  on Windows should expect to correct something.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $root
try {
    $appDir = 'apps\desktop'
    $version = (Select-String -Path "$appDir\pubspec.yaml" -Pattern '^version:\s*(.+)$' |
        Select-Object -First 1).Matches[0].Groups[1].Value.Trim()

    Write-Host "==> Building Remote Link $version for Windows" -ForegroundColor Cyan
    Push-Location $appDir
    try { flutter build windows --release } finally { Pop-Location }

    $releaseDir = Join-Path $root "$appDir\build\windows\x64\runner\Release"
    $exe = Join-Path $releaseDir 'remotelink_desktop.exe'
    if (-not (Test-Path $exe)) {
        throw "no executable at $exe - did the build actually succeed?"
    }

    $thumbprint = $env:RL_SIGN_THUMBPRINT
    $timestampUrl = if ($env:RL_TIMESTAMP_URL) { $env:RL_TIMESTAMP_URL }
                    else { 'http://timestamp.digicert.com' }

    function Invoke-Sign([string]$Path) {
        if (-not $thumbprint) { return }
        # /fd and /td both SHA256: the file digest and the timestamp digest are
        # separate settings, and leaving the timestamp at its SHA-1 default
        # produces a signature Windows will stop honouring.
        & signtool.exe sign `
            /sha1 $thumbprint `
            /fd SHA256 `
            /tr $timestampUrl `
            /td SHA256 `
            /d 'Remote Link' `
            $Path
        if ($LASTEXITCODE -ne 0) { throw "signtool failed on $Path" }
    }

    if ($thumbprint) {
        Write-Host "==> Signing the application" -ForegroundColor Cyan
        # The executable is signed before packaging, so the copy the installer
        # lays down on disk is the signed one. Signing only the installer leaves
        # an unsigned binary behind, which is what SmartScreen judges on every
        # launch after the first.
        Invoke-Sign $exe
        Get-ChildItem $releaseDir -Filter '*.dll' -Recurse |
            ForEach-Object { Invoke-Sign $_.FullName }
    }
    else {
        Write-Warning 'RL_SIGN_THUMBPRINT is not set - building unsigned.'
        Write-Warning 'SmartScreen will show "Windows protected your PC" and hide'
        Write-Warning 'the Run button behind "More info".'
    }

    Write-Host "==> Building the installer" -ForegroundColor Cyan
    $iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if (-not $iscc) {
        $candidate = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
        if (Test-Path $candidate) { $iscc = $candidate }
        else { throw 'Inno Setup 6 is not installed: https://jrsoftware.org/isdl.php' }
    }

    $outDir = Join-Path $root 'build\release'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    & $iscc "/DAppVersion=$version" "/DSourceDir=$releaseDir" `
        (Join-Path $PSScriptRoot 'remotelink.iss')
    if ($LASTEXITCODE -ne 0) { throw 'ISCC failed' }

    $installer = Join-Path $outDir "RemoteLink-$version-setup.exe"
    Invoke-Sign $installer

    Write-Host "==> Done: $installer" -ForegroundColor Green
}
finally {
    Pop-Location
}
