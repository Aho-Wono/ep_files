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
$configPath = Join-Path $PSScriptRoot 'organize.config.json'
$organizerPath = Join-Path $PSScriptRoot 'Organize-EpFiles.ps1'

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

function Assert-TrackedFilesClean {
    $trackedState = @(Get-GitOutput -Arguments @('status', '--porcelain', '--untracked-files=no') -FailureMessage 'Could not inspect the repository status.')
    if ($trackedState.Count -gt 0) {
        Write-Host 'Tracked file changes were found:' -ForegroundColor Yellow
        $trackedState | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Yellow }
        throw 'Publish stopped to avoid uploading a modification or deletion. Ask a Git user to review these changes.'
    }
}

function Test-RebaseInProgress {
    $gitDirectoryOutput = @(Get-GitOutput -Arguments @('rev-parse', '--git-dir') -FailureMessage 'Could not locate the Git metadata directory.')
    $gitDirectory = $gitDirectoryOutput[0]
    if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) {
        $gitDirectory = Join-Path $rootPath $gitDirectory
    }
    return ((Test-Path -LiteralPath (Join-Path $gitDirectory 'rebase-merge')) -or
        (Test-Path -LiteralPath (Join-Path $gitDirectory 'rebase-apply')))
}

function Reset-DataStaging {
    param([Parameter(Mandatory)][string[]] $Directories)

    if ($Directories.Count -gt 0) {
        & git -C $rootPath reset --quiet HEAD -- @Directories
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not restore the staging area after a validation failure.'
        }
    }
}

if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw "Repository directory not found: $rootPath"
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Organizer config not found: $configPath"
}
if (-not (Test-Path -LiteralPath $organizerPath -PathType Leaf)) {
    throw "Organizer script not found: $organizerPath"
}
if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or is not available in PATH.'
}

$repositoryTopOutput = @(Get-GitOutput -Arguments @('rev-parse', '--show-toplevel') -FailureMessage 'This directory is not a Git repository.')
$repositoryTop = [System.IO.Path]::GetFullPath($repositoryTopOutput[0]).TrimEnd('\', '/')
if (-not $repositoryTop.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Repository root mismatch. Expected: $rootPath, actual: $repositoryTop"
}

$branchOutput = @(Get-GitOutput -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -FailureMessage 'Could not determine the current branch.')
$branch = [string] $branchOutput[0]
if ([string]::IsNullOrWhiteSpace($branch) -or ($branch -eq 'HEAD')) {
    throw 'Sync requires a checked-out branch. Detached HEAD is not supported.'
}

[void] (Get-GitOutput -Arguments @('remote', 'get-url', 'origin') -FailureMessage 'The origin remote is not configured.')

if (Test-RebaseInProgress) {
    throw 'A Git rebase is already in progress. Ask a Git user to finish or abort it before syncing.'
}
Assert-TrackedFilesClean

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$extensionMap = @{}
$unregisteredEquipment = 'others'
foreach ($property in $config.extensionToEquipment.PSObject.Properties) {
    $extension = $property.Name.Trim().ToLowerInvariant()
    if (-not $extension.StartsWith('.')) {
        $extension = ".$extension"
    }
    $equipment = ([string] $property.Value).Trim()
    if ([string]::IsNullOrWhiteSpace($equipment) -or
        [System.IO.Path]::IsPathRooted($equipment) -or
        ($equipment -match '[\\/]') -or
        ($equipment -in @('.', '..'))) {
        throw "Invalid equipment directory in organizer config: $equipment"
    }
    $extensionMap[$extension] = $equipment
}
if ($extensionMap.Count -eq 0) {
    throw 'No extension rules were found in the organizer config.'
}
if ($null -ne $config.PSObject.Properties['unregisteredEquipment']) {
    $unregisteredEquipment = ([string] $config.unregisteredEquipment).Trim()
}
if ([string]::IsNullOrWhiteSpace($unregisteredEquipment) -or
    [System.IO.Path]::IsPathRooted($unregisteredEquipment) -or
    ($unregisteredEquipment -match '[\\/]') -or
    ($unregisteredEquipment -in @('.', '..'))) {
    throw "Invalid unregistered equipment directory in organizer config: $unregisteredEquipment"
}
if ($extensionMap.Values -contains $unregisteredEquipment) {
    throw "unregisteredEquipment must differ from registered equipment directories: $unregisteredEquipment"
}
$equipmentDirectories = @((@($extensionMap.Values) + $unregisteredEquipment) | Sort-Object -Unique)

Write-Host ("[1/5] Pulling origin/{0}..." -f $branch) -ForegroundColor Cyan
Invoke-Git -Arguments @('pull', '--rebase', 'origin', $branch) -FailureMessage 'Pull failed. No local machining data was deleted.'
Assert-TrackedFilesClean

Write-Host '[2/5] Organizing new machining data...' -ForegroundColor Cyan
& $organizerPath -Root $rootPath -ConfigPath $configPath -UntrackedOnly
Assert-TrackedFilesClean

Write-Host '[3/5] Validating and staging additions...' -ForegroundColor Cyan
$existingEquipmentDirectories = @($equipmentDirectories | Where-Object {
    Test-Path -LiteralPath (Join-Path $rootPath $_) -PathType Container
})
if ($existingEquipmentDirectories.Count -gt 0) {
    Invoke-Git -Arguments (@('add', '--ignore-removal', '--') + $existingEquipmentDirectories) -FailureMessage 'Could not stage machining data.'
}

$stagedEntries = @(Get-GitOutput -Arguments @('-c', 'core.quotepath=false', 'diff', '--cached', '--name-status') -FailureMessage 'Could not validate staged files.')
$invalidEntries = [System.Collections.Generic.List[string]]::new()
$oversizedEntries = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $stagedEntries) {
    $parts = $entry -split "`t", 2
    if (($parts.Count -ne 2) -or ($parts[0] -ne 'A')) {
        $invalidEntries.Add($entry)
        continue
    }

    $gitPath = $parts[1].Replace('\', '/')
    $segments = $gitPath.Split('/')
    if ($segments.Count -ne 3) {
        $invalidEntries.Add($entry)
        continue
    }

    $fileExtension = [System.IO.Path]::GetExtension($segments[2]).ToLowerInvariant()
    $parsedDate = [DateTime]::MinValue
    $validDate = [DateTime]::TryParseExact(
        $segments[1],
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $parsedDate
    )
    $expectedEquipment = if ($extensionMap.ContainsKey($fileExtension)) {
        $extensionMap[$fileExtension]
    }
    else {
        $unregisteredEquipment
    }
    if ((-not $segments[0].Equals($expectedEquipment, [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not $validDate)) {
        $invalidEntries.Add($entry)
        continue
    }

    $workingFilePath = Join-Path $rootPath $gitPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $workingFile = Get-Item -LiteralPath $workingFilePath
    if ($workingFile.Length -gt 100MB) {
        $oversizedEntries.Add(("{0} ({1:N1} MiB)" -f $gitPath, ($workingFile.Length / 1MB)))
    }
}

if ($invalidEntries.Count -gt 0) {
    Reset-DataStaging -Directories $existingEquipmentDirectories
    Write-Host 'Files rejected by the add-only safety check:' -ForegroundColor Yellow
    $invalidEntries | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Yellow }
    throw 'Only newly organized files under EQUIPMENT/YYYY-MM-DD can be uploaded.'
}
if ($oversizedEntries.Count -gt 0) {
    Reset-DataStaging -Directories $existingEquipmentDirectories
    Write-Host 'Files larger than the GitHub 100 MiB limit:' -ForegroundColor Yellow
    $oversizedEntries | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Yellow }
    throw 'Oversized files were not committed. Reduce or separately transfer them before syncing again.'
}

if ($stagedEntries.Count -gt 0) {
    $extensionCounts = @{}
    foreach ($entry in $stagedEntries) {
        $entryParts = $entry -split "`t", 2
        $entryExtension = [System.IO.Path]::GetExtension($entryParts[1]).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($entryExtension)) {
            $entryExtension = '<no extension>'
        }
        if ($extensionCounts.ContainsKey($entryExtension)) {
            $extensionCounts[$entryExtension]++
        }
        else {
            $extensionCounts[$entryExtension] = 1
        }
    }

    $summaryParts = @($extensionCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        "{0}: {1}" -f $_.Name, $_.Value
    })
    $fileWord = if ($stagedEntries.Count -eq 1) { 'file' } else { 'files' }
    $commitMessage = "Add {0} machining {1} ({2})" -f $stagedEntries.Count, $fileWord, ($summaryParts -join ', ')

    Write-Host 'Files to publish:' -ForegroundColor Cyan
    $extensionCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host ("  {0}: {1}" -f $_.Name, $_.Value) -ForegroundColor Cyan
    }
    Write-Host ("  Total: {0}" -f $stagedEntries.Count) -ForegroundColor Cyan
    Write-Host ("Commit message: {0}" -f $commitMessage) -ForegroundColor DarkGray

    $userName = @(& git -C $rootPath config --get user.name 2>$null)
    if (($LASTEXITCODE -ne 0) -or ($userName.Count -eq 0) -or [string]::IsNullOrWhiteSpace($userName[0])) {
        Invoke-Git -Arguments @('config', 'user.name', 'EP Files Facility') -FailureMessage 'Could not configure the local Git author name.'
        Write-Host 'Local Git author name set to: EP Files Facility' -ForegroundColor DarkGray
    }
    $userEmail = @(& git -C $rootPath config --get user.email 2>$null)
    if (($LASTEXITCODE -ne 0) -or ($userEmail.Count -eq 0) -or [string]::IsNullOrWhiteSpace($userEmail[0])) {
        Invoke-Git -Arguments @('config', 'user.email', 'ep-files-facility@localhost.invalid') -FailureMessage 'Could not configure the local Git author email.'
        Write-Host 'A private local-only Git author email was configured.' -ForegroundColor DarkGray
    }

    Invoke-Git -Arguments @('commit', '-m', $commitMessage) -FailureMessage 'Could not create the local commit.'
}
else {
    Write-Host 'No new machining files were found.' -ForegroundColor DarkGray
}

Write-Host ("[4/5] Checking origin/{0} again..." -f $branch) -ForegroundColor Cyan
& git -C $rootPath pull --rebase origin $branch
$secondPullExitCode = $LASTEXITCODE
if ($secondPullExitCode -ne 0) {
    if (Test-RebaseInProgress) {
        & git -C $rootPath rebase --abort
    }
    throw 'The final pull found a conflict or network error. Local files and commits were kept; ask a Git user to review it.'
}

Write-Host ("[5/5] Pushing origin/{0}..." -f $branch) -ForegroundColor Cyan
Invoke-Git -Arguments @('push', '--set-upstream', 'origin', $branch) -FailureMessage 'Push failed. Local files and commits were kept; run the design-PC command again after checking login and network access.'

$remainingStatus = @(Get-GitOutput -Arguments @('status', '--short') -FailureMessage 'Could not read the final repository status.')
Write-Host 'Publish complete.' -ForegroundColor Green
if ($remainingStatus.Count -gt 0) {
    Write-Host 'Some files were intentionally not uploaded:' -ForegroundColor Yellow
    $remainingStatus | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Yellow }
}
