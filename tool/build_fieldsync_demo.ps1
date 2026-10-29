#requires -Version 5.1
<#
.SYNOPSIS
    Task 4 B3 isolated demo APK build, provenance and artifact-security gate.

.DESCRIPTION
    Builds exactly one variant:
        demo / debug / lib/main_qa.dart / QA_PREVIEW=true
        package com.example.imaps_fieldsync.demo
    and verifies the resulting APK before reporting success.

    The script is fail-closed. It refuses to build unless the independent
    signer, package inventory, source state, toolchain and declared-asset
    checks all pass. It never installs, launches, records or captures.

    Private signing secrets are read only from the process environment:
        FIELDSYNC_DEMO_KEYSTORE_PATH
        FIELDSYNC_DEMO_KEYSTORE_ALIAS
        FIELDSYNC_DEMO_KEYSTORE_PASSWORD
        FIELDSYNC_DEMO_KEY_PASSWORD
    They are never written to evidence, printed or passed on a command line.

    The approved public certificate fingerprint is nonsecret and must be
    supplied independently:
        -ExpectedSignerSha256 <64 hex>  or  FIELDSYNC_DEMO_SIGNER_SHA256
    It is never derived from the APK being checked.

    With -SourceCommit the script exports that exact reviewed commit with
    git archive into an isolated snapshot outside the repository and runs all
    source checks and the build against the snapshot. The live working tree
    is never copied and is never modified, so untracked logo-kit additions,
    the archive, ignored build outputs and unrelated local changes cannot
    enter the artifact.

.PARAMETER PreflightOnly
    Run every prerequisite check and stop before the Flutter build.

.PARAMETER SelfTest
    Run helper/negative-control assertions only. No build, git or device use.

.PARAMETER ExpectedSignerSha256
    Credential-owner-approved public certificate SHA-256 (nonsecret).

.PARAMETER FlutterPath
    Explicit flutter.bat. Defaults to the PATH entry or FIELDSYNC_FLUTTER_PATH.

.PARAMETER JavaHome
    Explicit JDK home. Defaults to JAVA_HOME. The script never auto-selects
    Android Studio's JBR; an operator must point JAVA_HOME/-JavaHome at it.

.PARAMETER DeviceSerial
    Required only when more than one usable adb device is attached.

.PARAMETER EvidenceRoot
    Parent directory for restricted local evidence. Defaults to
    %LOCALAPPDATA%\FieldSync\b3-evidence. Must be outside the repository.

.PARAMETER PublishedBaseline
    Published B1/B2 commit that must be an ancestor of HEAD.

.PARAMETER SourceCommit
    Full 40-hex SHA of the reviewed commit to export. Must equal local HEAD
    and current origin/main; the script never substitutes another revision.

.PARAMETER SnapshotParent
    Absolute parent directory for the isolated snapshot. Defaults to
    %LOCALAPPDATA%\FieldSync\b3-source. Must be outside the FieldSync
    repository, the iMAPS repository and the Command Center folder.

.NOTES
    Authorized variants are hardcoded. There is deliberately no flavor,
    build-type, target or package override parameter.
#>
[CmdletBinding()]
param(
    [switch]$PreflightOnly,
    [switch]$SelfTest,
    [string]$ExpectedSignerSha256 = $env:FIELDSYNC_DEMO_SIGNER_SHA256,
    [string]$FlutterPath = $env:FIELDSYNC_FLUTTER_PATH,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$DeviceSerial = "",
    [string]$EvidenceRoot = "",
    [string]$PublishedBaseline = "656d50f9a6f68ec6671e9aa9325a86d9490416a0",
    [string]$SourceCommit = "",
    [string]$SnapshotParent = ""
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:SourceRoot = $script:RepoRoot
$script:ScriptSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$script:SnapshotRequested = $false
$script:SnapshotDir = ''
$script:SnapshotCommit = ''
$script:SnapshotTree = ''
$script:SnapshotCreatedAt = ''
$script:SnapshotInventorySha256 = ''
$script:SnapshotVerified = $false
$script:SnapshotTrackedCount = 0
$script:SnapshotExcludedCount = 0
$script:SnapshotLogoKitPaths = @()
$script:Flavor = 'demo'
$script:BuildType = 'debug'
$script:Target = 'lib/main_qa.dart'
$script:PackageId = 'com.example.imaps_fieldsync.demo'
$script:DemoLabel = 'FieldSync DEMO'
$script:FixtureRevision = 'demo-fixtures-20261028-v1'
$script:FlutterVersion = '3.44.3'
$script:FlutterRevision = 'e1fd963c6f6922bd32afde2e9698a363cd0406d2'
$script:DartVersion = '3.12.2'
$script:GradleVersion = '8.14.5'
$script:EvidenceLog = $null
$script:Blockers = New-Object System.Collections.Generic.List[object]
$script:SelfTestFailures = 0

# Any unexpected terminating error aborts the run; it must never fall through
# to a success claim.
trap {
    $message = "B3 INTERNAL ERROR: $($_.Exception.Message)"
    Write-Host $message
    if ($script:EvidenceLog) {
        [IO.File]::AppendAllText(
            $script:EvidenceLog,
            "$(Get-Date -Format o) $message`r`n",
            (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false)
        )
    }
    exit 4
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
function Write-Evidence {
    param([string]$Message)
    $line = "$(Get-Date -Format o) $Message"
    if ($script:EvidenceLog) {
        [IO.File]::AppendAllText(
            $script:EvidenceLog,
            $line + "`r`n",
            (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false)
        )
    }
    Write-Host $Message
}

function Add-Blocker {
    param([string]$Code, [string]$Detail)
    $script:Blockers.Add([pscustomobject]@{ code = $Code; detail = $Detail })
    Write-Evidence "BLOCKER [$Code] $Detail"
}

function Get-TextSha256 {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    $output = & $FilePath @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($null -eq $output) { $output = @() }
    return [pscustomobject]@{
        Output = @($output | ForEach-Object { $_.ToString() })
        Code   = $code
    }
}

function Invoke-Git {
    param([string[]]$GitArgs)
    return Invoke-Native -FilePath 'git' -Arguments (@('--no-optional-locks', '-C', $script:RepoRoot) + $GitArgs)
}

function Get-FileText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw
}

function Normalize-Pin {
    param([string]$Pin)
    if (-not $Pin) { return '' }
    return ($Pin -replace '[:\s-]', '').ToLowerInvariant()
}

function Test-Sha256Pin {
    param([string]$Pin)
    $normalized = Normalize-Pin $Pin
    if ($normalized -notmatch '^[0-9a-f]{64}$') { return $false }
    # Reject obvious placeholders such as 000... or fff...
    if ($normalized -match '^(.)\1{63}$') { return $false }
    return $true
}

function Test-PathInsideRepo {
    param([string]$Path)
    $root = [IO.Path]::GetFullPath($script:RepoRoot).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-ForbiddenAssetName {
    param([string]$Name)
    $normalized = $Name.Replace('\', '/')
    $baseName = ($normalized -split '/')[-1]
    if ($baseName -eq '.env' -or $baseName.StartsWith('.env.') -or $baseName.EndsWith('.env')) {
        return $true
    }
    $extension = [IO.Path]::GetExtension($baseName).ToLowerInvariant()
    $forbidden = @(
        '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.bz2', '.xz',
        '.jar', '.apk', '.aab', '.war', '.ear',
        '.jks', '.keystore', '.p12', '.pfx', '.pem', '.key', '.kdbx'
    )
    if ($forbidden -contains $extension) { return $true }
    if ($baseName -match '^(secrets?|credentials?|service[-_]?account)(\..*)?$') { return $true }
    return $false
}

function Add-SourceHash {
    param([string]$Name, [string]$Path, [System.Collections.Specialized.OrderedDictionary]$Bag)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $Bag[$Name] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
        $Bag[$Name] = 'missing'
    }
}

function Get-DeclaredAssetRoots {
    param([string]$PubspecText)
    if (-not $PubspecText) { return @() }
    $roots = @()
    foreach ($match in [regex]::Matches($PubspecText, '(?m)^\s*-\s+(assets/[^\s#]+/)\s*$')) {
        $roots += $match.Groups[1].Value.TrimEnd('/')
    }
    return @($roots | Select-Object -Unique)
}

function Test-OriginalInventoryUnchanged {
    param([string]$ExpectedHash)
    $status = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.Code -ne 0) { return $false }
    $lines = @($status.Output | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Sort-Object)
    return ((Get-TextSha256 ($lines -join "`n")) -eq $ExpectedHash)
}

function Test-DeniedSnapshotParent {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-PathInsideRepo $full) { return 'the FieldSync repository' }
    $segments = $full.Split('\')
    if ($segments -contains 'iMAPS') { return 'the iMAPS repository' }
    if ($full.IndexOf('FieldSync_Command_Center', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return 'the canonical Command Center folder'
    }
    return ''
}

# ---------------------------------------------------------------------------
# self-test: negative controls for the pure helpers
# ---------------------------------------------------------------------------
if ($SelfTest) {
    function Assert-SelfTest {
        param([bool]$Condition, [string]$Name)
        if ($Condition) {
            Write-Host "PASS $Name"
        } else {
            Write-Host "FAIL $Name"
            $script:SelfTestFailures++
        }
    }

    Assert-SelfTest (Test-Sha256Pin ('0123456789abcdef' * 4)) 'accepts a 64-hex signer pin'
    Assert-SelfTest (Test-Sha256Pin ('AB:CD' + ('0' * 60))) 'normalizes colon-formatted pin'
    Assert-SelfTest (-not (Test-Sha256Pin 'xyz')) 'rejects malformed signer pin'
    Assert-SelfTest (-not (Test-Sha256Pin '')) 'rejects empty signer pin'
    Assert-SelfTest (-not (Test-Sha256Pin ('0' * 64))) 'rejects all-zero placeholder pin'
    Assert-SelfTest (-not (Test-Sha256Pin ('f' * 64))) 'rejects repeated-character placeholder pin'

    Assert-SelfTest (Test-ForbiddenAssetName 'assets/flutter_assets/.env') 'rejects packaged .env'
    Assert-SelfTest (Test-ForbiddenAssetName 'assets/flutter_assets/.env.production') 'rejects packaged .env.production'
    Assert-SelfTest (Test-ForbiddenAssetName 'assets/icon/FieldSync_Logo_1.zip') 'rejects packaged archive'
    Assert-SelfTest (Test-ForbiddenAssetName 'assets/keys/demo.jks') 'rejects packaged keystore'
    Assert-SelfTest (Test-ForbiddenAssetName 'assets/keys/demo.pem') 'rejects packaged key material'
    Assert-SelfTest (Test-ForbiddenAssetName 'assets/config/credentials.json') 'rejects credential file'
    Assert-SelfTest (-not (Test-ForbiddenAssetName 'assets/icon/logo.png')) 'accepts ordinary image'
    Assert-SelfTest (-not (Test-ForbiddenAssetName 'assets/maps/rosario_boundary.metadata.json')) 'accepts ordinary json'

    Assert-SelfTest (Test-PathInsideRepo (Join-Path $script:RepoRoot 'android')) 'detects in-repo path'
    Assert-SelfTest (-not (Test-PathInsideRepo (Join-Path $env:TEMP 'demo.keystore'))) 'accepts external path'

    $roots = Get-DeclaredAssetRoots "  assets:`n    - path: .env`n      flavors:`n        - prod`n    - assets/icon/`n    - assets/maps/`n"
    Assert-SelfTest (($roots -join ',') -eq 'assets/icon,assets/maps') 'parses declared asset roots'

    if ($script:SelfTestFailures -gt 0) {
        Write-Host "SELF-TEST FAILED: $script:SelfTestFailures"
        exit 1
    }
    Write-Host 'SELF-TEST PASSED'
    exit 0
}

# ---------------------------------------------------------------------------
# repository and evidence location
# ---------------------------------------------------------------------------
$gitRootResult = Invoke-Git @('rev-parse', '--show-toplevel')
if ($gitRootResult.Code -ne 0) {
    Write-Host 'B3 BLOCKED: the script is not inside a valid Git worktree.'
    exit 2
}
$actualRoot = [IO.Path]::GetFullPath(($gitRootResult.Output -join '').Trim()).TrimEnd('\')
if (-not $actualRoot.Equals([IO.Path]::GetFullPath($script:RepoRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "B3 BLOCKED: script parent '$($script:RepoRoot)' is not the Git root '$actualRoot'."
    exit 2
}

if (-not $EvidenceRoot) {
    if (-not $env:LOCALAPPDATA) {
        Write-Host 'B3 BLOCKED: LOCALAPPDATA is unavailable; pass -EvidenceRoot explicitly.'
        exit 2
    }
    $EvidenceRoot = Join-Path $env:LOCALAPPDATA 'FieldSync\b3-evidence'
}
if (-not [IO.Path]::IsPathRooted($EvidenceRoot)) {
    Write-Host "B3 BLOCKED: -EvidenceRoot must be an absolute path ('$EvidenceRoot')."
    exit 2
}
$evidenceDir = Join-Path $EvidenceRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
if (Test-PathInsideRepo $evidenceDir) {
    Write-Host "B3 BLOCKED: evidence root '$evidenceDir' is inside the repository."
    exit 2
}
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$script:EvidenceDir = $evidenceDir
$script:EvidenceLog = Join-Path $evidenceDir 'preflight.log'
Write-Evidence "B3 evidence directory: $evidenceDir"
Write-Evidence "Repository: $script:RepoRoot"
Write-Evidence "Script SHA-256: $script:ScriptSha256"

# ---------------------------------------------------------------------------
# source state
# ---------------------------------------------------------------------------
$headResult = Invoke-Git @('rev-parse', 'HEAD')
if ($headResult.Code -ne 0) {
    Add-Blocker 'SOURCE_UNREADABLE' 'git rev-parse HEAD failed.'
    $head = ''
} else {
    $head = ($headResult.Output -join '').Trim()
}
$treeResult = Invoke-Git @('rev-parse', 'HEAD^{tree}')
$headTree = if ($treeResult.Code -eq 0) { ($treeResult.Output -join '').Trim() } else { '' }

$ancestorResult = Invoke-Git @('merge-base', '--is-ancestor', $PublishedBaseline, 'HEAD')
if ($ancestorResult.Code -ne 0) {
    Add-Blocker 'SOURCE_BASELINE_NOT_ANCESTOR' "Published baseline $PublishedBaseline is not an ancestor of HEAD."
}

$remoteResult = Invoke-Git @('ls-remote', 'origin', 'refs/heads/main')
$remoteMain = ''
if ($remoteResult.Code -ne 0 -or $remoteResult.Output.Count -eq 0) {
    Add-Blocker 'REMOTE_STATE_UNVERIFIED' 'git ls-remote origin refs/heads/main failed; remote ancestry is unverified.'
} else {
    $remoteMain = (($remoteResult.Output -join ' ') -split '\s+')[0]
}

$statusResult = Invoke-Git @('status', '--porcelain=v1', '--untracked-files=all')
if ($statusResult.Code -ne 0) {
    Add-Blocker 'SOURCE_INVENTORY_UNREADABLE' 'git status failed; the dirty inventory is unavailable.'
    $statusLines = @()
} else {
    $statusLines = @($statusResult.Output | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

$dirtyPaths = @()
$buildAffectingDirty = @()
$buildAffectingPrefixes = @('android/', 'lib/', 'assets/', 'pubspec.yaml', 'pubspec.lock')
foreach ($line in $statusLines) {
    if ($line.Length -lt 4) { continue }
    $pathText = $line.Substring(3).Trim()
    if ($pathText -match ' -> ') { $pathText = ($pathText -split ' -> ')[-1] }
    $dirtyPaths += $pathText
    foreach ($prefix in $buildAffectingPrefixes) {
        if ($pathText.Equals($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            $pathText.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $buildAffectingDirty += $pathText
            break
        }
    }
}
$snapshotRequested = ($SourceCommit -ne '' -or $SnapshotParent -ne '')
$script:SnapshotRequested = $snapshotRequested
$script:SnapshotExcludedCount = $dirtyPaths.Count
if ($buildAffectingDirty.Count -gt 0 -and -not $snapshotRequested) {
    Add-Blocker 'BUILD_AFFECTING_DIRTY' ("{0} unreviewed dirty path(s) under build-affecting roots: {1}" -f `
        $buildAffectingDirty.Count, (($buildAffectingDirty | Select-Object -First 8) -join ', '))
} elseif ($buildAffectingDirty.Count -gt 0) {
    Write-Evidence "Snapshot isolation: $($buildAffectingDirty.Count) build-affecting dirty path(s) remain only in the live working tree and are excluded from the build."
}

$diffResult = Invoke-Git @('diff', 'HEAD', '--binary', '--no-ext-diff')
$dirtyDiffText = if ($diffResult.Code -eq 0) { $diffResult.Output -join "`n" } else { '' }
$dirtyDiffHash = Get-TextSha256 $dirtyDiffText
$inventoryHash = Get-TextSha256 (($statusLines | Sort-Object) -join "`n")

# ---------------------------------------------------------------------------
# isolated source snapshot: object export of one reviewed commit
# ---------------------------------------------------------------------------
if ($snapshotRequested) {
    if (-not $SnapshotParent) {
        if ($env:LOCALAPPDATA) {
            $SnapshotParent = Join-Path $env:LOCALAPPDATA 'FieldSync\b3-source'
        } else {
            Add-Blocker 'SNAPSHOT_PARENT_MISSING' 'LOCALAPPDATA is unavailable; pass -SnapshotParent explicitly.'
        }
    }
    if ($SnapshotParent -and -not [IO.Path]::IsPathRooted($SnapshotParent)) {
        Add-Blocker 'SNAPSHOT_PARENT_NOT_ABSOLUTE' "Snapshot parent must be an absolute path ('$SnapshotParent')."
    }
    $deniedParent = ''
    if ($SnapshotParent -and [IO.Path]::IsPathRooted($SnapshotParent)) {
        $deniedParent = Test-DeniedSnapshotParent $SnapshotParent
        if ($deniedParent) {
            Add-Blocker 'SNAPSHOT_PARENT_DENIED' "Snapshot parent must not be inside $deniedParent."
        }
    }

    $normalizedCommit = $SourceCommit.Trim().ToLowerInvariant()
    if ($normalizedCommit -notmatch '^[0-9a-f]{40}$') {
        Add-Blocker 'SNAPSHOT_COMMIT_MALFORMED' 'SourceCommit must be a full 40-hex commit SHA.'
    } else {
        $typeResult = Invoke-Git @('cat-file', '-t', $normalizedCommit)
        $commitType = if ($typeResult.Code -eq 0) { ($typeResult.Output -join '').Trim() } else { '' }
        if ($commitType -ne 'commit') {
            Add-Blocker 'SNAPSHOT_COMMIT_UNKNOWN' "SourceCommit '$normalizedCommit' is not a commit in this repository."
        } elseif ($head -and $normalizedCommit -ne $head.ToLowerInvariant()) {
            Add-Blocker 'SNAPSHOT_COMMIT_NOT_HEAD' "Reviewed commit '$normalizedCommit' is not local HEAD '$head'; no revision substitution is performed."
        }
        if ($remoteMain -and $normalizedCommit -ne $remoteMain.ToLowerInvariant()) {
            Add-Blocker 'SNAPSHOT_REMOTE_MISMATCH' "Reviewed commit '$normalizedCommit' does not match origin/main '$remoteMain'."
        }
        $treeForCommit = Invoke-Git @('rev-parse', "$normalizedCommit^{tree}")
        if ($treeForCommit.Code -ne 0) {
            Add-Blocker 'SNAPSHOT_TREE_UNREADABLE' 'The reviewed commit tree could not be resolved.'
        } else {
            $script:SnapshotTree = ($treeForCommit.Output -join '').Trim()
            $script:SnapshotCommit = $normalizedCommit
        }
    }

    $snapshotRoot = ''
    if ($SnapshotParent -and [IO.Path]::IsPathRooted($SnapshotParent) -and -not $deniedParent -and $script:SnapshotCommit) {
        $snapshotStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $snapshotRoot = Join-Path $SnapshotParent ("b3-snapshot-" + $snapshotStamp)
        $snapshotSource = Join-Path $snapshotRoot 'source'
        New-Item -ItemType Directory -Force -Path $snapshotSource | Out-Null
        # All later source reads target the snapshot only; the live tree is
        # never used as a build input once snapshot mode is requested.
        $script:SourceRoot = $snapshotSource
        $script:SnapshotDir = $snapshotRoot
        $script:SnapshotCreatedAt = (Get-Date -Format o)

        $tarPath = Join-Path $snapshotRoot 'source.tar'
        # Force blob-faithful export: the machine's core.autocrlf=true would
        # otherwise rewrite line endings and break byte-level provenance.
        $archiveResult = Invoke-Git @('-c', 'core.autocrlf=false', 'archive', '--format=tar', "--output=$tarPath", $script:SnapshotCommit)
        if ($archiveResult.Code -ne 0 -or -not (Test-Path -LiteralPath $tarPath -PathType Leaf)) {
            Add-Blocker 'SNAPSHOT_EXPORT_FAILED' 'git archive of the reviewed commit failed; no trusted snapshot exists.'
        } else {
            $extractResult = Invoke-Native -FilePath 'tar.exe' -Arguments @('-xf', $tarPath, '-C', $snapshotSource)
            Remove-Item -LiteralPath $tarPath -Force -ErrorAction SilentlyContinue
            if ($extractResult.Code -ne 0) {
                Add-Blocker 'SNAPSHOT_EXTRACT_FAILED' 'Extraction of the reviewed commit archive failed.'
            }
        }

        $exportFailed = [bool]($script:Blockers | Where-Object {
            $_.code -eq 'SNAPSHOT_EXPORT_FAILED' -or $_.code -eq 'SNAPSHOT_EXTRACT_FAILED'
        })
        if (-not $exportFailed) {
            $treeList = Invoke-Git @('ls-tree', '-r', '--long', $script:SnapshotCommit)
            if ($treeList.Code -ne 0) {
                Add-Blocker 'SNAPSHOT_TREE_UNREADABLE' 'git ls-tree failed; snapshot content cannot be verified.'
            } else {
                $expected = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($line in $treeList.Output) {
                    if ($line -match '^\d+ blob ([0-9a-f]+)\s+(\d+)\t(.+)$') {
                        $expected[$Matches[3].Replace('\', '/')] = [pscustomobject]@{ size = [long]$Matches[2]; sha = $Matches[1] }
                    }
                }
                $actual = @(Get-ChildItem -LiteralPath $snapshotSource -Recurse -File -Force)
                $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                $mismatches = @()
                $inventoryLines = @()
                foreach ($file in $actual) {
                    $relative = $file.FullName.Substring($snapshotSource.Length).TrimStart('\').Replace('\', '/')
                    if (-not $expected.ContainsKey($relative)) { $mismatches += "unexpected:$relative"; continue }
                    [void]$seen.Add($relative)
                    if ($file.Length -ne $expected[$relative].size) { $mismatches += "size:$relative" }
                    $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    $inventoryLines += "$relative|$($file.Length)|$fileHash"
                }
                foreach ($key in $expected.Keys) {
                    if (-not $seen.Contains($key)) { $mismatches += "missing:$key" }
                }
                if (Test-Path -LiteralPath (Join-Path $snapshotSource '.git')) { $mismatches += 'unexpected:.git' }

                $script:SnapshotInventorySha256 = Get-TextSha256 (($inventoryLines | Sort-Object) -join "`n")
                $script:SnapshotTrackedCount = $actual.Count
                if ($mismatches.Count -gt 0) {
                    Add-Blocker 'SNAPSHOT_CONTENT_MISMATCH' ("Snapshot differs from the commit tree: {0}" -f (($mismatches | Select-Object -First 5) -join ', '))
                } else {
                    $script:SnapshotVerified = $true
                    Write-Evidence "Snapshot: $snapshotSource"
                    Write-Evidence "Snapshot commit: $($script:SnapshotCommit)"
                    Write-Evidence "Snapshot tree: $($script:SnapshotTree)"
                    Write-Evidence "Snapshot tracked files: $($script:SnapshotTrackedCount)"
                    Write-Evidence "Snapshot inventory SHA-256: $($script:SnapshotInventorySha256)"
                }

                $script:SnapshotLogoKitPaths = @($actual |
                    Where-Object { $_.FullName.Substring($snapshotSource.Length).TrimStart('\').Replace('\', '/') -like 'assets/icon/*' } |
                    ForEach-Object { $_.FullName.Substring($snapshotSource.Length).TrimStart('\').Replace('\', '/') } |
                    Sort-Object)
                $logoKitFindings = @($script:SnapshotLogoKitPaths | Where-Object { Test-ForbiddenAssetName $_ })
                if ($logoKitFindings.Count -gt 0) {
                    Add-Blocker 'SNAPSHOT_TRACKED_ASSET_FORBIDDEN' ("Tracked assets are not packageable under B3 rules: {0}" -f (($logoKitFindings | Select-Object -First 5) -join ', '))
                } elseif ($script:SnapshotLogoKitPaths.Count -gt 0) {
                    Write-Evidence ("Tracked logo resources in snapshot: {0}" -f ($script:SnapshotLogoKitPaths -join ', '))
                }
                if (Test-Path -LiteralPath (Join-Path $snapshotSource 'assets/icon/FieldSync_Logo_1.zip')) {
                    Add-Blocker 'SNAPSHOT_UNTRACKED_ARCHIVE' 'The untracked logo archive is present in the snapshot.'
                }
                if (Test-Path -LiteralPath (Join-Path $snapshotSource 'assets/icon/FieldSync-Logo-Kit/app-icons')) {
                    Add-Blocker 'SNAPSHOT_UNTRACKED_LOGO_KIT' 'Untracked logo-kit additions are present in the snapshot.'
                }
            }
        }
    }

    # The live repository is read-only throughout: compare before and after.
    if (-not (Test-OriginalInventoryUnchanged $inventoryHash)) {
        Add-Blocker 'ORIGINAL_REPO_CHANGED' 'The live repository working-tree inventory changed while the snapshot was prepared.'
    }
}

$fixtureText = Get-FileText (Join-Path $script:SourceRoot 'lib/qa/demo_fixtures.dart')
$fixtureRevisionActual = ''
if ($fixtureText -and $fixtureText -match "static const revision = '([^']+)'") {
    $fixtureRevisionActual = $Matches[1]
}
if ($fixtureRevisionActual -ne $script:FixtureRevision) {
    Add-Blocker 'FIXTURE_REVISION_DRIFT' "Expected fixture revision '$($script:FixtureRevision)', found '$fixtureRevisionActual'."
}
$sourceStateHash = Get-TextSha256 ("HEAD=$head`nTREE=$headTree`nDIFF=$dirtyDiffHash`nINVENTORY=$inventoryHash`nFIXTURE=$fixtureRevisionActual`nSNAPSHOT_COMMIT=$($script:SnapshotCommit)`nSNAPSHOT_INVENTORY=$($script:SnapshotInventorySha256)")

Write-Evidence "HEAD: $head"
Write-Evidence "HEAD tree: $headTree"
Write-Evidence "Remote main: $remoteMain"
Write-Evidence "Dirty diff SHA-256: $dirtyDiffHash"
Write-Evidence "Dirty inventory SHA-256: $inventoryHash"
Write-Evidence "Source-state SHA-256: $sourceStateHash"
Write-Evidence "Dirty paths: $($dirtyPaths.Count) (build-affecting: $($buildAffectingDirty.Count))"
Write-Evidence "Fixture revision: $fixtureRevisionActual"
Write-Evidence "Build source root: $($script:SourceRoot)"
if ($snapshotRequested) {
    Write-Evidence "Snapshot requested: commit $($script:SnapshotCommit); verified $($script:SnapshotVerified); exclusions $($dirtyPaths.Count) dirty path(s)."
}

# ---------------------------------------------------------------------------
# B1/B2 contract re-check (source tokens, no build)
# ---------------------------------------------------------------------------
$gradleText = Get-FileText (Join-Path $script:SourceRoot 'android/app/build.gradle.kts')
$demoManifestText = Get-FileText (Join-Path $script:SourceRoot 'android/app/src/demoDebug/AndroidManifest.xml')
$mainQaText = Get-FileText (Join-Path $script:SourceRoot 'lib/main_qa.dart')
$pubspecText = Get-FileText (Join-Path $script:SourceRoot 'pubspec.yaml')

$contractChecks = @(
    @{ Name = 'gradle demo package';    Text = $gradleText;       Needle = $script:PackageId },
    @{ Name = 'gradle demo label';      Text = $gradleText;       Needle = $script:DemoLabel },
    @{ Name = 'gradle demo target';     Text = $gradleText;       Needle = $script:Target },
    @{ Name = 'gradle QA preview';      Text = $gradleText;       Needle = 'QA_PREVIEW=true' },
    @{ Name = 'gradle signer pin';      Text = $gradleText;       Needle = 'FIELDSYNC_DEMO_SIGNER_SHA256' },
    @{ Name = 'gradle keystore path';   Text = $gradleText;       Needle = 'FIELDSYNC_DEMO_KEYSTORE_PATH' },
    @{ Name = 'gradle keystore alias';  Text = $gradleText;       Needle = 'FIELDSYNC_DEMO_KEYSTORE_ALIAS' },
    @{ Name = 'gradle keystore pass';   Text = $gradleText;       Needle = 'FIELDSYNC_DEMO_KEYSTORE_PASSWORD' },
    @{ Name = 'gradle key pass';        Text = $gradleText;       Needle = 'FIELDSYNC_DEMO_KEY_PASSWORD' },
    @{ Name = 'gradle prodRelease block'; Text = $gradleText;     Needle = 'prodRelease is blocked' },
    @{ Name = 'demoDebug INTERNET removal'; Text = $demoManifestText; Needle = 'tools:node="remove"' },
    @{ Name = 'demoDebug backup disabled';  Text = $demoManifestText; Needle = 'android:allowBackup="false"' },
    @{ Name = 'demoDebug launcher icon';    Text = $demoManifestText; Needle = 'ic_launcher_demo' },
    @{ Name = 'main_qa package guard';  Text = $mainQaText;       Needle = $script:PackageId },
    @{ Name = 'main_qa QA guard';       Text = $mainQaText;       Needle = 'QA_PREVIEW' },
    @{ Name = 'main_qa signer guard';   Text = $mainQaText;       Needle = 'FIELDSYNC_DEMO_SIGNER_SHA256' },
    @{ Name = 'pubspec prod-scoped .env'; Text = $pubspecText;    Needle = 'path: .env' }
)
foreach ($check in $contractChecks) {
    if ($null -eq $check.Text -or -not $check.Text.Contains($check.Needle)) {
        Add-Blocker 'CONTRACT_DRIFT' "Missing expected B1/B2 contract token: $($check.Name)."
    }
}
if ($pubspecText -and $pubspecText -notmatch '(?s)- path: \.env\s+flavors:\s+-\s+prod') {
    Add-Blocker 'CONTRACT_DRIFT' 'The root .env is not declared as a prod-only Flutter asset.'
}

# Declared asset trees must not contain archives, env files, keys or credentials.
$declaredAssetRoots = Get-DeclaredAssetRoots $pubspecText
$assetFindings = @()
foreach ($relativeRoot in $declaredAssetRoots) {
    $absoluteRoot = Join-Path $script:SourceRoot $relativeRoot
    if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
        Add-Blocker 'ASSET_ROOT_MISSING' "Declared asset root is missing: $relativeRoot"
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File -Force) {
        $relativePath = $file.FullName.Substring($script:SourceRoot.Length).TrimStart('\').Replace('\', '/')
        if (Test-ForbiddenAssetName $relativePath) {
            $assetFindings += $relativePath
        }
    }
}
if ($assetFindings.Count -gt 0) {
    Add-Blocker 'DECLARED_ASSET_FORBIDDEN_CONTENT' ("{0} forbidden file(s) in declared asset trees (archive/env/key/credential category): {1}" -f `
        $assetFindings.Count, (($assetFindings | Select-Object -First 5) -join ', '))
}

# ---------------------------------------------------------------------------
# signer inputs
# ---------------------------------------------------------------------------
$signingNames = @(
    'FIELDSYNC_DEMO_KEYSTORE_PATH',
    'FIELDSYNC_DEMO_KEYSTORE_ALIAS',
    'FIELDSYNC_DEMO_KEYSTORE_PASSWORD',
    'FIELDSYNC_DEMO_KEY_PASSWORD'
)
$missingSigning = @()
foreach ($name in $signingNames) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { $missingSigning += $name }
}
if ($missingSigning.Count -gt 0) {
    Add-Blocker 'SIGNER_INPUTS_MISSING' ("Missing external signing input(s): {0}. No default debug signer is substituted." -f ($missingSigning -join ', '))
} else {
    $keystorePath = $env:FIELDSYNC_DEMO_KEYSTORE_PATH
    if (-not [IO.Path]::IsPathRooted($keystorePath)) {
        Add-Blocker 'KEYSTORE_PATH_NOT_ABSOLUTE' 'The demo keystore path must be absolute.'
    } elseif (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
        Add-Blocker 'KEYSTORE_MISSING' 'The supplied demo keystore file does not exist.'
    } elseif ((Get-Item -LiteralPath $keystorePath).Length -le 0) {
        Add-Blocker 'KEYSTORE_EMPTY' 'The supplied demo keystore file is empty.'
    } elseif (Test-PathInsideRepo $keystorePath) {
        Add-Blocker 'KEYSTORE_INSIDE_REPO' 'The demo keystore must be outside the repository.'
    } else {
        Write-Evidence 'Signing inputs: present (values never logged). Keystore is outside the repository.'
    }
}

$normalizedPin = Normalize-Pin $ExpectedSignerSha256
$environmentPin = Normalize-Pin $env:FIELDSYNC_DEMO_SIGNER_SHA256
if ($environmentPin -and $normalizedPin -and $environmentPin -ne $normalizedPin) {
    Add-Blocker 'SIGNER_PIN_AMBIGUOUS' 'The parameter and environment signer pins differ.'
}
if (-not $normalizedPin) {
    Add-Blocker 'SIGNER_PIN_MISSING' 'No credential-owner-approved public certificate SHA-256 was supplied.'
} elseif (-not (Test-Sha256Pin $normalizedPin)) {
    Add-Blocker 'SIGNER_PIN_MALFORMED' 'The supplied signer pin is not a 64-hex SHA-256 value.'
} else {
    Write-Evidence "Approved signer pin supplied independently: $normalizedPin"
}

# ---------------------------------------------------------------------------
# toolchain
# ---------------------------------------------------------------------------
if (-not $FlutterPath) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) { $FlutterPath = $flutterCommand.Source }
}
$flutterRoot = ''
if (-not $FlutterPath -or -not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    Add-Blocker 'TOOL_FLUTTER_MISSING' 'flutter.bat was not found; pass -FlutterPath explicitly.'
} else {
    $versionRaw = Invoke-Native -FilePath $FlutterPath -Arguments @('--version', '--machine')
    $versionText = $versionRaw.Output -join "`n"
    $start = $versionText.IndexOf('{')
    $end = $versionText.LastIndexOf('}')
    $versionJson = $null
    if ($versionRaw.Code -eq 0 -and $start -ge 0 -and $end -gt $start) {
        try { $versionJson = $versionText.Substring($start, $end - $start + 1) | ConvertFrom-Json } catch { $versionJson = $null }
    }
    if ($null -eq $versionJson) {
        Add-Blocker 'TOOL_FLUTTER_VERSION_UNREADABLE' 'flutter --version --machine did not return parseable JSON.'
    } else {
        if ($versionJson.frameworkVersion -ne $script:FlutterVersion -or
            $versionJson.frameworkRevision -ne $script:FlutterRevision -or
            $versionJson.dartSdkVersion -ne $script:DartVersion) {
            Add-Blocker 'TOOL_FLUTTER_VERSION_MISMATCH' ("Expected Flutter {0} ({1}) / Dart {2}; found {3} ({4}) / Dart {5}." -f `
                $script:FlutterVersion, $script:FlutterRevision, $script:DartVersion,
                $versionJson.frameworkVersion, $versionJson.frameworkRevision, $versionJson.dartSdkVersion)
        } else {
            $flutterRoot = $versionJson.flutterRoot
            Write-Evidence "Flutter: $($versionJson.frameworkVersion) $($versionJson.frameworkRevision), Dart $($versionJson.dartSdkVersion), root $flutterRoot"
        }
    }
}

if (-not $JavaHome) {
    Add-Blocker 'TOOL_JAVA_HOME_UNSET' 'JAVA_HOME/-JavaHome is unset. Select a JDK 17+ explicitly; JBR is not auto-selected.'
} else {
    $javaExe = Join-Path $JavaHome 'bin\java.exe'
    if (-not (Test-Path -LiteralPath $javaExe -PathType Leaf)) {
        Add-Blocker 'TOOL_JAVA_MISSING' "java.exe not found under '$JavaHome'."
    } else {
        $javaResult = Invoke-Native -FilePath $javaExe -Arguments @('-version')
        $javaText = $javaResult.Output -join "`n"
        if ($javaText -match 'version "(\d+)') {
            $javaMajor = [int]$Matches[1]
            if ($javaMajor -lt 17) {
                Add-Blocker 'TOOL_JAVA_VERSION' "JDK $javaMajor is below the required 17."
            } else {
                $env:JAVA_HOME = $JavaHome
                $env:PATH = "$JavaHome\bin;$env:PATH"
                $firstJavaLine = ($javaResult.Output | Select-Object -First 1)
                Write-Evidence "JDK: $firstJavaLine (selected explicitly at $JavaHome)"
            }
        } else {
            Add-Blocker 'TOOL_JAVA_VERSION_UNREADABLE' 'java -version did not report a parseable version.'
        }
    }
}

$sdkFromEnvironment = $env:ANDROID_HOME
if (-not $sdkFromEnvironment) { $sdkFromEnvironment = $env:ANDROID_SDK_ROOT }
$sdkFromLocalProperties = ''
$localPropertiesPath = Join-Path $script:RepoRoot 'android/local.properties'
$localPropertiesText = Get-FileText $localPropertiesPath
if ($localPropertiesText -and $localPropertiesText -match '(?m)^sdk\.dir=(.+)$') {
    $sdkFromLocalProperties = $Matches[1].Trim().Replace('\\', '\').Replace('\:', ':')
}
$androidSdk = $sdkFromEnvironment
if (-not $androidSdk) { $androidSdk = $sdkFromLocalProperties }
if ($sdkFromEnvironment -and $sdkFromLocalProperties) {
    if (-not ([IO.Path]::GetFullPath($sdkFromEnvironment).TrimEnd('\').Equals(
        [IO.Path]::GetFullPath($sdkFromLocalProperties).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) {
        Add-Blocker 'TOOL_SDK_AMBIGUOUS' "ANDROID_HOME ('$sdkFromEnvironment') and android/local.properties ('$sdkFromLocalProperties') disagree."
    }
}
if (-not $androidSdk -or -not (Test-Path -LiteralPath $androidSdk -PathType Container)) {
    Add-Blocker 'TOOL_SDK_MISSING' 'The Android SDK path could not be resolved.'
} else {
    Write-Evidence "Android SDK: $androidSdk"
    if (-not (Test-Path -LiteralPath (Join-Path $androidSdk 'platforms/android-36') -PathType Container)) {
        Add-Blocker 'TOOL_SDK_PLATFORM_MISSING' 'Android platform android-36 is not installed; the script will not download it.'
    }
}

$apkanalyzer = ''
$aapt2 = ''
$apksigner = ''
$adb = ''
if ($androidSdk) {
    $apkanalyzer = Join-Path $androidSdk 'cmdline-tools/latest/bin/apkanalyzer.bat'
    if (-not (Test-Path -LiteralPath $apkanalyzer -PathType Leaf)) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $androidSdk 'cmdline-tools') -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'bin/apkanalyzer.bat' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($candidate) { $apkanalyzer = $candidate }
    }
    if (-not (Test-Path -LiteralPath $apkanalyzer -PathType Leaf)) {
        Add-Blocker 'TOOL_APKANALYZER_MISSING' 'apkanalyzer.bat was not found; artifact identity cannot be inspected.'
    }

    $buildToolsRoot = Join-Path $androidSdk 'build-tools'
    $buildTools = Get-ChildItem -LiteralPath $buildToolsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe') -PathType Leaf)
        } |
        Select-Object -First 1
    if ($null -eq $buildTools) {
        Add-Blocker 'TOOL_BUILD_TOOLS_MISSING' 'No build-tools directory contains both apksigner and aapt2.'
    } else {
        $apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
        $aapt2 = Join-Path $buildTools.FullName 'aapt2.exe'
        Write-Evidence "Android build-tools: $($buildTools.Name)"
    }

    $adb = Join-Path $androidSdk 'platform-tools/adb.exe'
    if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
        Add-Blocker 'TOOL_ADB_MISSING' 'adb was not found; package collision cannot be verified.'
    }
}

$wrapperPath = Join-Path $script:SourceRoot 'android/gradle/wrapper/gradle-wrapper.properties'
$wrapperText = Get-FileText $wrapperPath
if (-not $wrapperText -or $wrapperText -notmatch [regex]::Escape("gradle-$($script:GradleVersion)-")) {
    Add-Blocker 'TOOL_GRADLE_WRAPPER_DRIFT' "The Gradle wrapper is not $($script:GradleVersion)."
} else {
    Write-Evidence "Gradle wrapper: $($script:GradleVersion)"
}
Write-Evidence 'ZIP inspection: System.IO.Compression (built-in); SHA-256: Get-FileHash (built-in).'

# ---------------------------------------------------------------------------
# package collision inventory (read-only; never installs or uninstalls)
# ---------------------------------------------------------------------------
$packageCollision = 'unverified'
if ($adb -and (Test-Path -LiteralPath $adb -PathType Leaf)) {
    $devicesResult = Invoke-Native -FilePath $adb -Arguments @('devices', '-l')
    $usable = @()
    $unusable = @()
    foreach ($line in $devicesResult.Output) {
        if ($line -match '^(\S+)\s+device\b') { $usable += $Matches[1] }
        elseif ($line -match '^(\S+)\s+(unauthorized|offline|no permissions)') { $unusable += $line.Trim() }
    }
    if ($unusable.Count -gt 0) {
        Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' "Attached device(s) are not usable for inspection: $($unusable -join '; ')"
    }
    if ($devicesResult.Code -ne 0) {
        Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' 'adb devices failed.'
    } elseif ($usable.Count -eq 0) {
        Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' 'No adb device is attached; package isolation for the demo package is unverified.'
    } elseif ($usable.Count -gt 1 -and -not $DeviceSerial) {
        Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' "Multiple devices attached ($($usable -join ', ')); pass -DeviceSerial explicitly."
    } else {
        $selectedSerial = $DeviceSerial
        if (-not $selectedSerial) { $selectedSerial = $usable[0] }
        if ($usable -notcontains $selectedSerial) {
            Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' "Selected device '$selectedSerial' is not attached."
        } else {
            $modelResult = Invoke-Native -FilePath $adb -Arguments @('-s', $selectedSerial, 'shell', 'getprop', 'ro.product.model')
            $apiResult = Invoke-Native -FilePath $adb -Arguments @('-s', $selectedSerial, 'shell', 'getprop', 'ro.build.version.sdk')
            Write-Evidence "Package inventory device: $($modelResult.Output -join ''), API $($apiResult.Output -join '')"
            $usersResult = Invoke-Native -FilePath $adb -Arguments @('-s', $selectedSerial, 'shell', 'pm', 'list', 'users')
            $userIds = @()
            foreach ($line in $usersResult.Output) {
                if ($line -match 'UserInfo\{(\d+):') { $userIds += $Matches[1] }
            }
            if ($usersResult.Code -ne 0 -or $userIds.Count -eq 0) {
                Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' 'Android user/profile inventory could not be read.'
            } else {
                $conflict = $false
                foreach ($userId in ($userIds | Select-Object -Unique)) {
                    $packageResult = Invoke-Native -FilePath $adb -Arguments @('-s', $selectedSerial, 'shell', 'pm', 'list', 'packages', '--user', $userId)
                    if ($packageResult.Code -ne 0) {
                        Add-Blocker 'PACKAGE_COLLISION_UNVERIFIED' "Package inventory failed for Android user $userId."
                        $conflict = $true
                        break
                    }
                    if ($packageResult.Output -match ('^package:' + [regex]::Escape($script:PackageId) + '$')) {
                        $conflict = $true
                        break
                    }
                }
                if ($conflict -and ($script:Blockers | Where-Object { $_.code -eq 'PACKAGE_COLLISION_UNVERIFIED' })) {
                    # already recorded
                } elseif ($conflict) {
                    Add-Blocker 'PACKAGE_COLLISION_CONFLICT' "An installation of $($script:PackageId) already exists; do not replace or modify it."
                } else {
                    $packageCollision = 'clear'
                    Write-Evidence "Package collision: clear for $($script:PackageId) across $($userIds.Count) Android user(s)."
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# decide whether a build may start
# ---------------------------------------------------------------------------
$preflightPass = ($script:Blockers.Count -eq 0)
$blockerArray = [object[]]$script:Blockers
$keystoreOutsideRepo = $null
if ($missingSigning.Count -eq 0) {
    $keystoreOutsideRepo = -not (Test-PathInsideRepo $env:FIELDSYNC_DEMO_KEYSTORE_PATH)
}
$reportBase = [ordered]@{
    generated_at = (Get-Date -Format o)
    status = 'PREFLIGHT'
    preflight_pass = $preflightPass
    build = 'not attempted'
    capture = 'OFF - no install, launch, screenshot or recording'
    source = [ordered]@{
        repo = $script:RepoRoot
        build_source_root = $script:SourceRoot
        script_sha256 = $script:ScriptSha256
        powershell = $PSVersionTable.PSVersion.ToString()
        head = $head
        head_tree = $headTree
        remote_main = $remoteMain
        published_baseline = $PublishedBaseline
        dirty_diff_sha256 = $dirtyDiffHash
        dirty_inventory_sha256 = $inventoryHash
        source_state_sha256 = $sourceStateHash
        dirty_paths = $dirtyPaths.Count
        build_affecting_dirty_paths = @($buildAffectingDirty)
        fixture_revision = $fixtureRevisionActual
    }
    snapshot = [ordered]@{
        requested = $snapshotRequested
        commit = $script:SnapshotCommit
        tree = $script:SnapshotTree
        path = $script:SnapshotDir
        created_at = $script:SnapshotCreatedAt
        tracked_files = $script:SnapshotTrackedCount
        inventory_sha256 = $script:SnapshotInventorySha256
        verified = $script:SnapshotVerified
        excluded_dirty_paths = $script:SnapshotExcludedCount
        tracked_icon_assets = @($script:SnapshotLogoKitPaths)
    }
    signer = [ordered]@{
        inputs_present = ($missingSigning.Count -eq 0)
        keystore_outside_repo = $keystoreOutsideRepo
        approved_public_sha256 = $normalizedPin
    }
    package_collision = $packageCollision
    tools = [ordered]@{
        flutter = $FlutterPath
        flutter_root = $flutterRoot
        java_home = $JavaHome
        android_sdk = $androidSdk
        apkanalyzer = $apkanalyzer
        aapt2 = $aapt2
        apksigner = $apksigner
        adb = $adb
    }
    blockers = $blockerArray
}

if (-not $preflightPass) {
    $reportBase['status'] = 'BLOCKED'
    Write-Evidence "PREFLIGHT FAILED with $($script:Blockers.Count) blocker(s)."
    $jsonPath = Join-Path $evidenceDir 'report.json'
    $reportBase | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $summaryPath = Join-Path $evidenceDir 'report.md'
    $lines = @(
        '# B3 preflight report',
        '',
        "- Time: $($reportBase.generated_at)",
        '- Status: BLOCKED',
        "- HEAD: $head",
        "- Remote main: $remoteMain",
        "- Build source root: $($script:SourceRoot)",
        "- Snapshot commit: $($script:SnapshotCommit) (verified: $($script:SnapshotVerified))",
        "- Snapshot inventory SHA-256: $($script:SnapshotInventorySha256)",
        "- Dirty paths: $($dirtyPaths.Count) (build-affecting: $($buildAffectingDirty.Count))",
        "- Signer inputs present: $($missingSigning.Count -eq 0)",
        "- Signer pin: $normalizedPin",
        "- Package collision: $packageCollision",
        '',
        '## Blockers'
    )
    foreach ($blocker in $script:Blockers) { $lines += "- [$($blocker.code)] $($blocker.detail)" }
    $lines += ''
    $lines += 'No build, install, launch or capture was performed.'
    $lines | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host ''
    Write-Host "B3 STATUS: BLOCKED (preflight) - see $evidenceDir"
    exit 1
}

if ($PreflightOnly) {
    $reportBase['status'] = 'PREFLIGHT PASS'
    $reportBase | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceDir 'report.json') -Encoding UTF8
    Write-Host ''
    Write-Host "B3 STATUS: PREFLIGHT PASS - build not attempted because -PreflightOnly was supplied."
    Write-Host "Evidence: $evidenceDir"
    exit 0
}

# ---------------------------------------------------------------------------
# one explicit demo build
# ---------------------------------------------------------------------------
$buildStarted = Get-Date
Write-Evidence "BUILD START $($buildStarted.ToString('o')) in $($script:SourceRoot): flutter build apk --debug --flavor demo --target $($script:Target) --dart-define=QA_PREVIEW=true --dart-define=FIELDSYNC_DEMO_SIGNER_SHA256=<approved pin>"

$buildRoot = Join-Path $script:SourceRoot 'build'
$secretValues = @(
    $env:FIELDSYNC_DEMO_KEYSTORE_PASSWORD,
    $env:FIELDSYNC_DEMO_KEY_PASSWORD
) | Where-Object { -not [string]::IsNullOrEmpty($_) }

$buildCode = $null
$buildArgs = @(
    'build', 'apk',
    '--debug',
    '--flavor', $script:Flavor,
    '--target', $script:Target,
    '--dart-define=QA_PREVIEW=true',
    "--dart-define=FIELDSYNC_DEMO_SIGNER_SHA256=$normalizedPin"
)
$buildLines = New-Object System.Collections.Generic.List[string]
Push-Location -LiteralPath $script:SourceRoot
try {
    & $FlutterPath @buildArgs 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $buildLines.Add($line)
        Write-Host $line
    }
    $buildCode = $LASTEXITCODE
} finally {
    Pop-Location
}
$buildEnded = Get-Date
$buildLogText = ($buildLines -join "`n")

$logPath = Join-Path $evidenceDir 'build.log'
$secretLeak = $false
$shortSecretPresent = @($secretValues | Where-Object { $_.Length -lt 4 }).Count -gt 0
foreach ($secret in $secretValues) {
    if ($secret.Length -ge 4 -and $buildLogText.Contains($secret)) { $secretLeak = $true }
}
if ($shortSecretPresent) {
    'Build log not preserved: a signing secret shorter than 4 characters is configured.' |
        Set-Content -LiteralPath $logPath -Encoding UTF8
} elseif ($secretLeak) {
    'REDACTED: the build output contained signing material and was not preserved.' |
        Set-Content -LiteralPath $logPath -Encoding UTF8
    Add-Blocker 'SECRET_IN_BUILD_LOG' 'The build output contained a signing secret; the log was discarded and redacted.'
} else {
    $buildLogText | Set-Content -LiteralPath $logPath -Encoding UTF8
}

if ($buildCode -ne 0) {
    Add-Blocker 'BUILD_FAILED' "flutter build apk exited with code $buildCode."
}

$apkPath = $null
$apkHash = ''
$freshApkPaths = @()
if ($buildCode -eq 0) {
    $freshApks = @()
    foreach ($apk in Get-ChildItem -LiteralPath $buildRoot -Recurse -Filter '*.apk' -File -ErrorAction SilentlyContinue) {
        if ($apk.LastWriteTime -ge $buildStarted.AddMinutes(-2)) {
            $freshApks += $apk
        }
    }
    # Gradle and the Flutter tool can publish byte-identical copies at two
    # paths. Accept copies of one artifact; reject distinct artifacts.
    $freshGroups = @()
    if ($freshApks.Count -gt 0) {
        $freshGroups = @($freshApks | Group-Object {
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    if ($freshGroups.Count -ne 1) {
        Add-Blocker 'ARTIFACT_NOT_FRESH' "Expected one fresh APK identity; found $($freshGroups.Count) distinct fresh artifact(s). A stale artifact is never accepted."
    } else {
        $chosen = $freshGroups[0].Group | Where-Object { $_.FullName -match '\\flutter-apk\\' } | Select-Object -First 1
        if (-not $chosen) { $chosen = $freshGroups[0].Group[0] }
        $apkPath = $chosen.FullName
        $apkHash = $freshGroups[0].Name
        $freshApkPaths = @($freshGroups[0].Group | ForEach-Object { $_.FullName })
        Write-Evidence "APK: $apkPath"
        Write-Evidence "Fresh APK copies: $($freshApkPaths.Count)"
        Write-Evidence "APK SHA-256: $apkHash"
    }
}

# ---------------------------------------------------------------------------
# consolidated artifact-security verification
# ---------------------------------------------------------------------------
$verification = [ordered]@{
    application_id = $null
    debuggable = $null
    label = $null
    icon = $null
    allow_backup = $null
    permissions = @()
    internet_present = $null
    asset_count = 0
    forbidden_assets = @()
    production_config_markers = @()
    entrypoint_provenance = $null
    signer_count = $null
    signer_dn = $null
    signer_sha256 = $null
    signature_valid = $null
}

if ($apkPath) {
    $manifestResult = Invoke-Native -FilePath $apkanalyzer -Arguments @('manifest', 'print', $apkPath)
    $manifestXml = $manifestResult.Output -join "`n"
    if ($manifestResult.Code -ne 0 -or -not $manifestXml) {
        Add-Blocker 'APK_MANIFEST_UNREADABLE' 'apkanalyzer could not print the merged manifest.'
    } else {
        if ($manifestXml -match 'package="([^"]+)"') { $verification['application_id'] = $Matches[1] }
        if ($verification.application_id -ne $script:PackageId) {
            Add-Blocker 'APK_IDENTITY' "Packaged application id is '$($verification.application_id)', expected '$($script:PackageId)'."
        }
        if ($manifestXml -match 'android:label="([^"]*)"') { $verification['label'] = $Matches[1] }
        if ($verification.label -ne $script:DemoLabel) {
            Add-Blocker 'APK_LABEL' "Packaged label is '$($verification.label)', expected '$($script:DemoLabel)'."
        }
        if ($manifestXml -match 'android:allowBackup="([^"]*)"') { $verification['allow_backup'] = $Matches[1] }
        if ($verification.allow_backup -ne 'false') {
            Add-Blocker 'APK_BACKUP' 'Packaged allowBackup is not false.'
        }

        $iconReference = ''
        if ($manifestXml -match 'android:icon="([^"]+)"') { $iconReference = $Matches[1] }
        $iconResource = ''
        if ($iconReference -match '^@ref/(0x[0-9a-fA-F]+)$') {
            $iconId = $Matches[1].ToLowerInvariant()
            $resourceDump = Invoke-Native -FilePath $aapt2 -Arguments @('dump', 'resources', $apkPath)
            foreach ($line in $resourceDump.Output) {
                if ($line -match ('^\s*resource\s+' + [regex]::Escape($iconId) + '\s+(\S+)')) {
                    $iconResource = $Matches[1]
                    break
                }
            }
        } elseif ($iconReference -match '^@(drawable|mipmap)/(.+)$') {
            $iconResource = "$($Matches[1])/$($Matches[2])"
        }
        $verification['icon'] = $iconResource
        if ($iconResource -ne 'drawable/ic_launcher_demo') {
            Add-Blocker 'APK_ICON' "Packaged launcher icon resolves to '$iconResource', expected 'drawable/ic_launcher_demo'."
        }
    }

    $debuggableResult = Invoke-Native -FilePath $apkanalyzer -Arguments @('manifest', 'debuggable', $apkPath)
    $verification['debuggable'] = ($debuggableResult.Output -join '').Trim()
    if ($debuggableResult.Code -ne 0 -or $verification.debuggable -ne 'true') {
        Add-Blocker 'APK_DEBUGGABLE' 'The artifact is not reported as debuggable.'
    }

    $permissionsResult = Invoke-Native -FilePath $apkanalyzer -Arguments @('manifest', 'permissions', $apkPath)
    $permissions = @()
    foreach ($line in $permissionsResult.Output) {
        $token = ($line -split '\s+')[0].Trim()
        if ($token) { $permissions += $token }
    }
    $verification['permissions'] = $permissions
    if ($permissionsResult.Code -ne 0) {
        Add-Blocker 'APK_PERMISSIONS_UNREADABLE' 'apkanalyzer could not list permissions.'
    }
    $verification['internet_present'] = ($permissions -contains 'android.permission.INTERNET')
    if ($verification.internet_present) {
        Add-Blocker 'APK_INTERNET_PRESENT' 'The packaged manifest contains android.permission.INTERNET.'
    }
    if ($manifestXml -match 'android\.permission\.INTERNET') {
        Add-Blocker 'APK_INTERNET_PRESENT' 'The merged manifest XML still declares android.permission.INTERNET.'
    }
    $deniedNetwork = @(
        'android.permission.INTERNET',
        'android.permission.CHANGE_NETWORK_STATE',
        'android.permission.ACCESS_WIFI_STATE',
        'android.permission.CHANGE_WIFI_STATE',
        'android.permission.NEARBY_WIFI_DEVICES',
        'android.permission.BLUETOOTH',
        'android.permission.BLUETOOTH_ADMIN',
        'android.permission.BLUETOOTH_CONNECT',
        'android.permission.BLUETOOTH_SCAN',
        'android.permission.UWB_RANGING'
    )
    $deniedPrivileged = @(
        'android.permission.REQUEST_INSTALL_PACKAGES',
        'android.permission.SYSTEM_ALERT_WINDOW',
        'android.permission.MANAGE_EXTERNAL_STORAGE',
        'android.permission.WRITE_SECURE_SETTINGS',
        'android.permission.PACKAGE_USAGE_STATS',
        'android.permission.READ_PRIVILEGED_PHONE_STATE'
    )
    foreach ($denied in ($deniedNetwork + $deniedPrivileged)) {
        if ($permissions -contains $denied) {
            Add-Blocker 'APK_UNEXPECTED_PERMISSION' "Unexpected network/privileged permission in the artifact: $denied"
        }
    }
    if ($permissions -contains 'android.permission.ACCESS_NETWORK_STATE') {
        Write-Evidence 'Permission note: ACCESS_NETWORK_STATE is present (non-socket, inherited from the connectivity plugin); recorded for review.'
    }

    $summaryResult = Invoke-Native -FilePath $apkanalyzer -Arguments @('apk', 'summary', $apkPath)
    $apkSummary = ($summaryResult.Output -join ' ').Trim()

    # Complete packaged entry inventory plus content checks (redacted reporting).
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($apkPath)
    } catch {
        Add-Blocker 'APK_ZIP_UNREADABLE' 'The APK ZIP container could not be opened.'
    }
    if ($archive) {
        try {
            $assetEntries = @()
            $forbiddenEntries = @()
            $markerHits = @()
            $kernelBytes = $null
            $assetCount = 0
            foreach ($entry in $archive.Entries) {
                $entryName = $entry.FullName
                if ($entryName -like 'assets/*') {
                    $assetCount++
                    if ($entryName -notlike '*/') { $assetEntries += $entryName }
                    if (Test-ForbiddenAssetName $entryName) { $forbiddenEntries += $entryName }
                }
                if ($entryName -eq 'assets/flutter_assets/kernel_blob.bin') {
                    $stream = $entry.Open()
                    try {
                        $memory = New-Object IO.MemoryStream
                        $stream.CopyTo($memory)
                        $kernelBytes = $memory.ToArray()
                    } finally {
                        $stream.Dispose()
                    }
                }
            }
            $verification['asset_count'] = $assetCount
            $verification['forbidden_assets'] = @($forbiddenEntries)

            if ($forbiddenEntries.Count -gt 0) {
                Add-Blocker 'APK_FORBIDDEN_ASSET' ("{0} forbidden packaged asset(s) (archive/env/key/credential category): {1}" -f `
                    $forbiddenEntries.Count, (($forbiddenEntries | Select-Object -First 5) -join ', '))
            }

            $textExtensions = @('.json', '.txt', '.yaml', '.yml', '.csv', '.md', '.geojson', '.xml', '.ini', '.cfg', '.conf', '.properties')
            $markers = @('SUPABASE_URL=', 'SUPABASE_ANON_KEY=', 'SUPABASE_SERVICE_ROLE', 'service_role', '-----BEGIN ', '.supabase.co')
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName -notlike 'assets/flutter_assets/assets/*') { continue }
                if ($entry.Length -le 0 -or $entry.Length -gt 2MB) { continue }
                $extension = [IO.Path]::GetExtension($entry.Name).ToLowerInvariant()
                if ($textExtensions -notcontains $extension) { continue }
                $reader = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8, $true)
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
                foreach ($marker in $markers) {
                    if ($content.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $markerHits += "$($entry.FullName) [$marker]"
                        break
                    }
                }
            }
            $verification['production_config_markers'] = @($markerHits)
            if ($markerHits.Count -gt 0) {
                Add-Blocker 'APK_PRODUCTION_CONFIG' ("{0} packaged asset(s) matched a production-configuration marker (content not retained)." -f $markerHits.Count)
            }

            if ($null -eq $kernelBytes) {
                Add-Blocker 'APK_ENTRYPOINT_UNVERIFIED' 'kernel_blob.bin is absent; the demo entrypoint cannot be verified.'
            } else {
                $kernelText = [Text.Encoding]::GetEncoding(28591).GetString($kernelBytes)
                $hasTarget = $kernelText.Contains('main_qa.dart')
                $hasFixture = $kernelText.Contains($script:FixtureRevision)
                $hasQaDefine = $kernelText.Contains('QA_PREVIEW')
                $verification['entrypoint_provenance'] = [ordered]@{
                    main_qa = $hasTarget
                    fixture_revision = $hasFixture
                    qa_preview = $hasQaDefine
                }
                if (-not ($hasTarget -and $hasFixture -and $hasQaDefine)) {
                    Add-Blocker 'APK_ENTRYPOINT_UNVERIFIED' 'The packaged Dart kernel does not prove main_qa + fixture revision + QA_PREVIEW.'
                }
            }
        } finally {
            $archive.Dispose()
        }
    }

    # Actual APK signature verification.
    $signatureResult = Invoke-Native -FilePath $apksigner -Arguments @('verify', '--verbose', '--print-certs', $apkPath)
    $signatureText = $signatureResult.Output -join "`n"
    if ($signatureResult.Code -ne 0 -or $signatureText -notmatch '(?m)^Verifies\s*$') {
        Add-Blocker 'APK_SIGNATURE_INVALID' 'apksigner did not report a valid signature.'
    } else {
        $verification['signature_valid'] = $true
    }
    if ($signatureText -match 'Number of signers:\s*(\d+)') { $verification['signer_count'] = [int]$Matches[1] }
    if ($verification.signer_count -ne 1) {
        Add-Blocker 'APK_SIGNER_COUNT' 'The artifact does not have exactly one signer.'
    }
    $digestMatches = [regex]::Matches($signatureText, 'Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)')
    if ($digestMatches.Count -ne 1) {
        Add-Blocker 'APK_SIGNER_UNREADABLE' 'Exactly one certificate SHA-256 digest was not reported.'
    } else {
        $verification['signer_sha256'] = Normalize-Pin $digestMatches[0].Groups[1].Value
        if ($verification.signer_sha256 -ne $normalizedPin) {
            Add-Blocker 'APK_SIGNER_MISMATCH' 'The actual certificate SHA-256 does not match the independently approved pin.'
        }
    }
    if ($signatureText -match 'Signer #1 certificate DN:\s*(.+)') {
        $verification['signer_dn'] = $Matches[1].Trim()
        if ($verification.signer_dn -match 'CN=Android Debug') {
            Add-Blocker 'APK_DEBUG_SIGNER' 'The artifact is signed by the Android default debug certificate.'
        }
    } else {
        Add-Blocker 'APK_SIGNER_UNREADABLE' 'The signer certificate DN was not reported.'
    }
    Write-Evidence "APK summary: $apkSummary"
    Write-Evidence "APK permissions: $($permissions -join ', ')"
    Write-Evidence "APK signer DN: $($verification.signer_dn)"
    Write-Evidence "APK signer SHA-256: $($verification.signer_sha256)"
}

# ---------------------------------------------------------------------------
# result
# ---------------------------------------------------------------------------
if (-not (Test-OriginalInventoryUnchanged $inventoryHash)) {
    Add-Blocker 'ORIGINAL_REPO_CHANGED' 'The live repository working-tree inventory changed during the build/verification run.'
}
$report = $reportBase
$report['status'] = if ($script:Blockers.Count -eq 0) { 'VERIFIED APK' } elseif ($buildCode -ne 0) { 'BUILD FAILED' } else { 'ARTIFACT REJECTED' }
$report['build'] = if ($buildCode -eq 0) { 'succeeded' } else { "failed (exit $buildCode)" }
$report['build_started_at'] = $buildStarted.ToString('o')
$report['build_ended_at'] = $buildEnded.ToString('o')
$report['completed_at'] = (Get-Date -Format o)
$report['apk'] = [ordered]@{
    path = $apkPath
    sha256 = $apkHash
    fresh = ($null -ne $apkPath)
    fresh_copies = @($freshApkPaths)
}
$report['verification'] = $verification
$report['blockers'] = [object[]]$script:Blockers
$report['capture'] = 'OFF - no install, launch, screenshot or recording'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidenceDir 'report.json') -Encoding UTF8

$summary = @(
    '# B3 build/verification report',
    '',
    "- Time: $($report.generated_at)",
    "- Status: $($report.status)",
    "- HEAD: $head",
    "- Remote main: $remoteMain",
    "- Source-state SHA-256: $sourceStateHash",
    "- Fixture revision: $fixtureRevisionActual",
    "- Build source root: $($script:SourceRoot)",
    "- Snapshot commit: $($script:SnapshotCommit)",
    "- Snapshot inventory SHA-256: $($script:SnapshotInventorySha256)",
    "- Snapshot verified: $($script:SnapshotVerified)",
    "- Build: $($report.build)",
    "- APK: $apkPath",
    "- APK SHA-256: $apkHash",
    "- Application id: $($verification.application_id)",
    "- Label: $($verification.label)",
    "- Icon: $($verification.icon)",
    "- Debuggable: $($verification.debuggable)",
    "- INTERNET present: $($verification.internet_present)",
    "- Signer DN: $($verification.signer_dn)",
    "- Signer SHA-256: $($verification.signer_sha256)",
    "- Signature valid: $($verification.signature_valid)",
    "- Capture: OFF",
    '',
    '## Blockers'
)
foreach ($blocker in $script:Blockers) { $summary += "- [$($blocker.code)] $($blocker.detail)" }
$summary += ''
$summary | Set-Content -LiteralPath (Join-Path $evidenceDir 'report.md') -Encoding UTF8

Write-Host ''
if ($script:Blockers.Count -eq 0) {
    Write-Host "B3 STATUS: VERIFIED APK - $apkPath"
    Write-Host "APK SHA-256: $apkHash"
    Write-Host "Evidence: $evidenceDir"
    exit 0
}
Write-Host "B3 STATUS: ARTIFACT REJECTED - see $evidenceDir"
exit 3
