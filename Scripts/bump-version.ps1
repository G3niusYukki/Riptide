<#
.SYNOPSIS
    Bump the Riptide version across the four cross-platform version files.

.DESCRIPTION
    Mirrors Scripts/bump-version.sh (macOS) for the Windows side of the
    Riptide catchup plan. Synchronizes the canonical version number to:

      - .version                                       (canonical)
      - riptide-windows/package.json                   (npm)
      - riptide-windows/src-tauri/tauri.conf.json      (Tauri config)
      - riptide-windows/src-tauri/Cargo.toml           ([package] section)

    The script does NOT commit, tag, or push. A human must review the
    diff (printed at the end) and commit manually.

    The four target files are copied to .bump-backup/<UTC-timestamp>/
    with their relative paths preserved before any modification, so the
    bump is fully reversible with a recursive copy.

.PARAMETER NewVersion
    Target version in the form X.Y.Z (e.g. 2.4.2). Must match
    ^\d+\.\d+\.\d+$ exactly. Prerelease tags and build metadata are
    not supported by this script (see Scripts/bump-version.sh for the
    macOS variant that accepts them).

.PARAMETER DryRun
    Print the planned changes without writing any file or creating any
    backup directory. Use this to verify a bump before running it for
    real.

.EXAMPLE
    pwsh ./Scripts/bump-version.ps1 2.4.2 -DryRun
    # Show which files would change and the planned version transitions.

.EXAMPLE
    pwsh ./Scripts/bump-version.ps1 2.4.2
    # Bump to 2.4.2. Backups under .bump-backup/<timestamp>/.

.NOTES
    Author : Riptide Catchup / rust-engineer (Phase A, A4)
    Mirrors Scripts/bump-version.sh (macOS).
    Tested on PowerShell 7.6+ on Windows.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $NewVersion,

    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths ---------------------------------------------------------------
$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$VersionFile = Join-Path $RepoRoot '.version'
$PackageJson = Join-Path $RepoRoot 'riptide-windows/package.json'
$TauriConf   = Join-Path $RepoRoot 'riptide-windows/src-tauri/tauri.conf.json'
$CargoToml   = Join-Path $RepoRoot 'riptide-windows/src-tauri/Cargo.toml'

# Ordered so the printed list goes: canonical -> npm -> Tauri -> Cargo
$Targets = [ordered]@{
    '.version'                                  = $VersionFile
    'riptide-windows/package.json'              = $PackageJson
    'riptide-windows/src-tauri/tauri.conf.json' = $TauriConf
    'riptide-windows/src-tauri/Cargo.toml'      = $CargoToml
}

# --- Validation ----------------------------------------------------------
$VersionPattern = '^\d+\.\d+\.\d+$'
if ($NewVersion -notmatch $VersionPattern) {
    throw "Invalid version '$NewVersion'. Expected pattern $VersionPattern (e.g. 2.4.2)."
}

if (-not (Test-Path $VersionFile)) {
    throw "Canonical version file not found: $VersionFile"
}
foreach ($name in $Targets.Keys) {
    if (-not (Test-Path $Targets[$name])) {
        throw "Target file not found: $($Targets[$name])"
    }
}

$CurrentVersion = (Get-Content -Raw $VersionFile).Trim()
if ($CurrentVersion -eq $NewVersion) {
    Write-Host "Nothing to do: .version is already $NewVersion" -ForegroundColor Yellow
    return
}

Write-Host '=========================================='
Write-Host "Bumping version: $CurrentVersion -> $NewVersion"
Write-Host '=========================================='

# --- DryRun branch -------------------------------------------------------
if ($DryRun) {
    Write-Host ''
    Write-Host 'DRY RUN: no files will be modified, no backup created.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Files that would be updated:'
    foreach ($name in $Targets.Keys) {
        Write-Host "  - $name"
    }
    Write-Host ''
    Write-Host 'Planned changes:'
    Write-Host ("  {0,-48} : version={1} -> {2}" -f '.version', $CurrentVersion, $NewVersion)
    Write-Host ("  {0,-48} : version={1} -> {2}" -f 'riptide-windows/package.json', $CurrentVersion, $NewVersion)
    Write-Host ("  {0,-48} : version={1} -> {2}" -f 'riptide-windows/src-tauri/tauri.conf.json', $CurrentVersion, $NewVersion)
    Write-Host ("  {0,-48} : [package].version={1} -> {2}" -f 'riptide-windows/src-tauri/Cargo.toml', $CurrentVersion, $NewVersion)
    Write-Host ''
    Write-Host 'Backup would be created at: .bump-backup/<UTC-timestamp>/'
    Write-Host ''
    return
}

# --- Backup --------------------------------------------------------------
$Timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$BackupRoot = Join-Path $RepoRoot ".bump-backup/$Timestamp"

if (-not (Test-Path $BackupRoot)) {
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
}
foreach ($name in $Targets.Keys) {
    $src  = $Targets[$name]
    $dest = Join-Path $BackupRoot $name
    $destDir = Split-Path $dest -Parent
    if ($destDir -ne $BackupRoot -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    Copy-Item -Path $src -Destination $dest -Force
}
Write-Host "Backup created: $BackupRoot"

# --- 1) Update canonical .version ----------------------------------------
[System.IO.File]::WriteAllText(
    $VersionFile,
    ($NewVersion + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)
$Confirmed = (Get-Content -Raw $VersionFile).Trim()
if ($Confirmed -ne $NewVersion) {
    throw "Sanity check failed: .version reads '$Confirmed' after write (expected '$NewVersion')."
}
Write-Host 'OK .version'

# --- 2) Read .version, then update the other 3 ---------------------------
$Canonical = (Get-Content -Raw $VersionFile).Trim()
if ($Canonical -ne $NewVersion) {
    throw "Aborting: .version is '$Canonical' but target was '$NewVersion'."
}

# Helper: write a file as UTF-8 (no BOM) with LF line endings so the
# result matches the LF convention used elsewhere in the repo.
function Write-TextFileLf {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )
    $normalized = $Content -replace "`r`n", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

# package.json
$pkg = Get-Content -Raw $PackageJson | ConvertFrom-Json
$pkg.version = $NewVersion
Write-TextFileLf -Path $PackageJson -Content ($pkg | ConvertTo-Json -Depth 100)
Write-Host 'OK riptide-windows/package.json'

# tauri.conf.json
$tauri = Get-Content -Raw $TauriConf | ConvertFrom-Json
$tauri.version = $NewVersion
Write-TextFileLf -Path $TauriConf -Content ($tauri | ConvertTo-Json -Depth 100)
Write-Host 'OK riptide-windows/src-tauri/tauri.conf.json'

# Cargo.toml — regex in the [package] section
$cargo       = Get-Content -Raw $CargoToml
$pattern     = '(?ms)(\[package\][^\[]*?^version\s*=\s*)"[^"]+"'
$replacement = '${1}"' + $NewVersion + '"'
$newCargo    = $cargo -replace $pattern, $replacement
if ($newCargo -eq $cargo) {
    throw "Failed to update Cargo.toml: pattern 'version = ""...""' under [package] not found."
}
Write-TextFileLf -Path $CargoToml -Content $newCargo
Write-Host 'OK riptide-windows/src-tauri/Cargo.toml'

# --- Show diff -----------------------------------------------------------
Write-Host ''
Write-Host '=========================================='
Write-Host 'git diff --stat'
Write-Host '=========================================='
Push-Location $RepoRoot
try {
    $diffStat = git diff --stat -- .version `
        riptide-windows/package.json `
        riptide-windows/src-tauri/tauri.conf.json `
        riptide-windows/src-tauri/Cargo.toml
    if ([string]::IsNullOrWhiteSpace($diffStat)) {
        Write-Host '(no changes)'
    } else {
        Write-Host $diffStat
    }

    Write-Host ''
    Write-Host '=========================================='
    Write-Host 'git diff --no-color'
    Write-Host '=========================================='
    $diff = git diff --no-color -- .version `
        riptide-windows/package.json `
        riptide-windows/src-tauri/tauri.conf.json `
        riptide-windows/src-tauri/Cargo.toml
    if ([string]::IsNullOrWhiteSpace($diff)) {
        Write-Host '(no changes)'
    } else {
        Write-Host $diff
    }
} catch {
    Write-Warning "git diff failed: $_"
} finally {
    Pop-Location
}

Write-Host ''
Write-Host '=========================================='
Write-Host "Version bumped to $NewVersion"
Write-Host "Backup: $BackupRoot"
Write-Host ''
Write-Host 'Next: review the diff above, then:'
Write-Host "  git add -A"
Write-Host "  git commit -m 'chore: bump version to $NewVersion'"
Write-Host "  git tag v$NewVersion"
Write-Host '=========================================='
