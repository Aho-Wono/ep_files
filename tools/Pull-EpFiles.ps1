[CmdletBinding()]
param(
    [Parameter()]
    [string] $Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    Write-Host ''
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    & git -C $rootPath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("{0} (Git exit code: {1})" -f $FailureMessage, $exitCode)
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    $output = @(& git -C $rootPath @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("{0} (Git exit code: {1})" -f $FailureMessage, $exitCode)
    }
    return $output
}

if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw "Repository directory not found: $rootPath"
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or is not available in PATH.'
}

$repositoryTopOutput = @(Get-GitOutput -Arguments @('rev-parse', '--show-toplevel') -FailureMessage 'This directory is not a Git repository.')
$repositoryTop = [System.IO.Path]::GetFullPath($repositoryTopOutput[0]).TrimEnd('\', '/')
if (-not $repositoryTop.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository root mismatch. Expected: $rootPath, actual: $repositoryTop"
}

$trackedState = @(Get-GitOutput -Arguments @('status', '--porcelain', '--untracked-files=no') -FailureMessage 'Could not inspect the repository status.')
if ($trackedState.Count -gt 0) {
    Write-Host 'Tracked file changes were found:' -ForegroundColor Yellow
    $trackedState | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Yellow }
    throw 'Update stopped so local changes are not overwritten. Ask a Git user to review this PC.'
}

$branchOutput = @(Get-GitOutput -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -FailureMessage 'Could not determine the current branch.')
$branch = [string] $branchOutput[0]
if ([string]::IsNullOrWhiteSpace($branch) -or ($branch -eq 'HEAD')) {
    throw 'Update requires a checked-out branch. Detached HEAD is not supported.'
}
[void] (Get-GitOutput -Arguments @('remote', 'get-url', 'origin') -FailureMessage 'The origin remote is not configured.')

Write-Host ("[1/2] Fetching origin/{0}..." -f $branch) -ForegroundColor Cyan
Invoke-Git -Arguments @('fetch', 'origin', $branch) -FailureMessage 'Could not download the latest repository data. Check the network connection.'

$localCommit = [string] (@(Get-GitOutput -Arguments @('rev-parse', 'HEAD') -FailureMessage 'Could not inspect the local revision.'))[0]
$remoteCommit = [string] (@(Get-GitOutput -Arguments @('rev-parse', 'FETCH_HEAD') -FailureMessage 'Could not inspect the downloaded revision.'))[0]

if (-not $localCommit.Equals($remoteCommit, [System.StringComparison]::OrdinalIgnoreCase)) {
    & git -C $rootPath merge-base --is-ancestor HEAD FETCH_HEAD
    $ancestorExitCode = $LASTEXITCODE
    if ($ancestorExitCode -eq 1) {
        throw 'This facility PC contains local commits or a diverged history. No files were changed; ask a Git user to repair it.'
    }
    if ($ancestorExitCode -ne 0) {
        throw 'Could not compare the local and remote histories.'
    }

    Write-Host '[2/2] Applying the downloaded update...' -ForegroundColor Cyan
    Invoke-Git -Arguments @('merge', '--ff-only', 'FETCH_HEAD') -FailureMessage 'The downloaded update could not be applied safely. Local files were kept.'
}
else {
    Write-Host '[2/2] This PC is already up to date.' -ForegroundColor DarkGray
}

$latestCommit = @(Get-GitOutput -Arguments @('log', '-1', '--format=%h  %cd  %s', '--date=format-local:%Y-%m-%d %H:%M') -FailureMessage 'Could not display the latest revision.')
Write-Host 'Latest machining data is ready.' -ForegroundColor Green
Write-Host ("Revision: {0}" -f $latestCommit[0]) -ForegroundColor DarkGray
