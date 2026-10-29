[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9][a-z0-9._-]{0,47}$')]
    [string]$AgentName,

    [string]$SkillsRoot = (Join-Path $env:USERPROFILE '.agents\skills'),

    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedSkillHash = '6073F9842709B5422C73D07A5A461408F125501DBBCBE627045148B4497D6107'
$SkillSource = Join-Path $PSScriptRoot 'SKILL.md'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Get-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent
    )

    $child = Get-FullPath $Path
    $root = Get-FullPath $Parent
    if (-not $child.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected parent: $child"
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Verify-Install {
    param([Parameter(Mandatory)][string]$SkillRoot)

    $skill = Join-Path $SkillRoot 'SKILL.md'
    $namespacePath = Join-Path $SkillRoot 'AGENT-NAMESPACE.txt'
    if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) {
        throw "Missing SKILL.md: $skill"
    }
    if (-not (Test-Path -LiteralPath $namespacePath -PathType Leaf)) {
        throw "Missing AGENT-NAMESPACE.txt: $namespacePath"
    }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $skill).Hash.ToUpperInvariant()
    if ($actual -ne $ExpectedSkillHash) {
        throw "SKILL.md hash mismatch. Expected=$ExpectedSkillHash Actual=$actual"
    }

    $bytes = [IO.File]::ReadAllBytes($namespacePath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "AGENT-NAMESPACE.txt contains a UTF-8 BOM"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($text -cne $AgentName) {
        throw "AGENT-NAMESPACE.txt must contain '$AgentName', found '$text'"
    }
}

if (-not (Test-Path -LiteralPath $SkillSource -PathType Leaf)) {
    throw "Package is incomplete: missing $SkillSource"
}
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SkillSource).Hash.ToUpperInvariant()
if ($sourceHash -ne $ExpectedSkillHash) {
    throw "Packaged SKILL.md hash mismatch. Expected=$ExpectedSkillHash Actual=$sourceHash"
}

$destination = Join-Path $SkillsRoot 'ego-browser-agent'
Assert-ChildPath -Path $destination -Parent $SkillsRoot

if ($VerifyOnly) {
    Verify-Install -SkillRoot $destination
    Write-Output "Verify OK: $destination (agent=$AgentName)"
    exit 0
}

if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $SkillsRoot -Force | Out-Null
}

if (Test-Path -LiteralPath $destination) {
    $existing = Get-Item -LiteralPath $destination -Force
    if ($existing.LinkType) {
        throw "Refusing to replace a link/junction: $destination"
    }
    if (-not $existing.PSIsContainer) {
        throw "Existing skill path is not a directory: $destination"
    }
    $backupDestination = Join-Path $SkillsRoot ('.ego-browser-agent-backup-' + $Timestamp)
    Assert-ChildPath -Path $backupDestination -Parent $SkillsRoot
    if (Test-Path -LiteralPath $backupDestination) {
        throw "Backup destination already exists: $backupDestination"
    }
    Move-Item -LiteralPath $destination -Destination $backupDestination
    Write-Output "Backed up existing skill: $backupDestination"
}

$stage = Join-Path $SkillsRoot ('.ego-browser-agent.stage-' + $PID + '-' + $Timestamp)
Assert-ChildPath -Path $stage -Parent $SkillsRoot
if (Test-Path -LiteralPath $stage) {
    throw "Staging path already exists: $stage"
}

try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -LiteralPath $SkillSource -Destination (Join-Path $stage 'SKILL.md')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AGENT-USAGE.md') -Destination (Join-Path $stage 'AGENT-USAGE.md')
    Write-Utf8NoBom -Path (Join-Path $stage 'AGENT-NAMESPACE.txt') -Text $AgentName
    Verify-Install -SkillRoot $stage
    Move-Item -LiteralPath $stage -Destination $destination
}
catch {
    if (Test-Path -LiteralPath $stage) {
        Assert-ChildPath -Path $stage -Parent $SkillsRoot
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    throw
}

Verify-Install -SkillRoot $destination
Write-Output "Install OK: $destination (agent=$AgentName)"
Write-Output "SKILL.md SHA-256: $ExpectedSkillHash"
