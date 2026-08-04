[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string] $Root,

    [Parameter()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateSet('GitFirstAdded', 'CreationTime', 'LastWriteTime')]
    [string] $DateSource,

    [Parameter()]
    [switch] $UntrackedOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function Get-NormalizedExtension {
    param([Parameter(Mandatory)][string] $Extension)

    $normalized = $Extension.Trim().ToLowerInvariant()
    if (-not $normalized.StartsWith('.')) {
        $normalized = ".$normalized"
    }
    return $normalized
}

function Get-GitRelativePath {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][System.IO.FileInfo] $File
    )

    # System.IO.Path.GetRelativePath is unavailable in Windows PowerShell 5.1.
    $rootWithSeparator = $RepositoryRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $rootUri = [Uri] $rootWithSeparator
    $fileUri = [Uri] $File.FullName
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString())
}

function Get-GitFirstAddedDate {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][System.IO.FileInfo] $File
    )

    $gitPath = Get-GitRelativePath -RepositoryRoot $RepositoryRoot -File $File

    try {
        $dates = @(& git -C $RepositoryRoot log --follow --diff-filter=A --format=%aI -- $gitPath 2>$null)
        if (($LASTEXITCODE -eq 0) -and ($dates.Count -gt 0)) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($dates[-1], [ref] $parsed)) {
                return $parsed.LocalDateTime
            }
        }
    }
    catch {
        # Fall back to CreationTime if Git is unavailable or this is not a repository.
    }

    return $null
}

function Test-GitTracked {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][System.IO.FileInfo] $File
    )

    $gitPath = Get-GitRelativePath -RepositoryRoot $RepositoryRoot -File $File
    $trackedPaths = @(& git -C $RepositoryRoot ls-files -- $gitPath 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        return ($trackedPaths.Count -gt 0)
    }
    throw "Could not check Git tracking state for: $gitPath"
}

function Get-FileDate {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][System.IO.FileInfo] $File,
        [Parameter(Mandatory)][string] $Source
    )

    switch ($Source) {
        'GitFirstAdded' {
            $gitDate = Get-GitFirstAddedDate -RepositoryRoot $RepositoryRoot -File $File
            if ($null -ne $gitDate) {
                return $gitDate
            }
            return $File.CreationTime
        }
        'CreationTime' { return $File.CreationTime }
        'LastWriteTime' { return $File.LastWriteTime }
        default { throw "Unsupported dateSource: $Source" }
    }
}

function Get-AvailableDestination {
    param(
        [Parameter(Mandatory)][string] $Directory,
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $ReservedPaths
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)
    $candidate = Join-Path $Directory $FileName
    $suffix = 2

    while ((Test-Path -LiteralPath $candidate) -or $ReservedPaths.Contains($candidate)) {
        $candidate = Join-Path $Directory ("{0} ({1}){2}" -f $baseName, $suffix, $extension)
        $suffix++
    }

    [void] $ReservedPaths.Add($candidate)
    return $candidate
}

function Test-IsOrganizedLocation {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $Equipment,
        [Parameter(Mandatory)][System.IO.FileInfo] $File
    )

    $equipmentDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Equipment)).TrimEnd('\', '/')
    if (($null -eq $File.Directory) -or ($null -eq $File.Directory.Parent)) {
        return $false
    }
    if (-not $File.Directory.Parent.FullName.Equals($equipmentDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $parsedDate = [DateTime]::MinValue
    return [DateTime]::TryParseExact(
        $File.Directory.Name,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $parsedDate
    )
}

$rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw "Target directory not found: $rootPath"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'organize.config.json'
}
$configFullPath = [System.IO.Path]::GetFullPath($ConfigPath)

$extensionMap = @{
    '.cnc' = 'CNC'
    '.stl' = 'STL'
}
$configuredDateSource = 'GitFirstAdded'

if (Test-Path -LiteralPath $configFullPath -PathType Leaf) {
    $config = Get-Content -LiteralPath $configFullPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($null -ne $config.extensionToEquipment) {
        $extensionMap = @{}
        foreach ($property in $config.extensionToEquipment.PSObject.Properties) {
            $extension = Get-NormalizedExtension -Extension $property.Name
            $equipment = [string] $property.Value
            if ([string]::IsNullOrWhiteSpace($equipment)) {
                throw "The equipment directory for $extension is empty."
            }
            if ([System.IO.Path]::IsPathRooted($equipment) -or
                ($equipment -match '[\\/]') -or
                ($equipment -in @('.', '..'))) {
                throw "The equipment value must be a single directory name: $equipment"
            }
            $extensionMap[$extension] = $equipment
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string] $config.dateSource)) {
        $configuredDateSource = [string] $config.dateSource
    }
}

if (-not [string]::IsNullOrWhiteSpace($DateSource)) {
    $configuredDateSource = $DateSource
}
if ($configuredDateSource -notin @('GitFirstAdded', 'CreationTime', 'LastWriteTime')) {
    throw 'dateSource must be GitFirstAdded, CreationTime, or LastWriteTime.'
}
if ($extensionMap.Count -eq 0) {
    throw 'extensionToEquipment does not contain any file extensions.'
}

$gitDirectory = Join-Path $rootPath '.git'
$reservedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$moves = [System.Collections.Generic.List[object]]::new()
$skipped = 0
$trackedSkipped = 0

$files = Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force | Where-Object {
    -not $_.FullName.StartsWith(($gitDirectory + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
}

foreach ($file in $files) {
    $extension = $file.Extension.ToLowerInvariant()
    if (-not $extensionMap.ContainsKey($extension)) {
        continue
    }

    $equipment = $extensionMap[$extension]
    if (Test-IsOrganizedLocation -RepositoryRoot $rootPath -Equipment $equipment -File $file) {
        $skipped++
        continue
    }
    if ($UntrackedOnly -and (Test-GitTracked -RepositoryRoot $rootPath -File $file)) {
        $trackedSkipped++
        continue
    }

    $fileDate = Get-FileDate -RepositoryRoot $rootPath -File $file -Source $configuredDateSource
    $dateFolder = $fileDate.ToString('yyyy-MM-dd')
    $destinationDirectory = Join-Path (Join-Path $rootPath $equipment) $dateFolder
    $idealDestination = Join-Path $destinationDirectory $file.Name

    if ($file.FullName.Equals($idealDestination, [System.StringComparison]::OrdinalIgnoreCase)) {
        $skipped++
        continue
    }

    $destination = Get-AvailableDestination -Directory $destinationDirectory -FileName $file.Name -ReservedPaths $reservedPaths
    $moves.Add([pscustomobject]@{
        Source      = $file.FullName
        Destination = $destination
        Equipment   = $equipment
        Date         = $dateFolder
    })
}

foreach ($move in $moves) {
    if ($PSCmdlet.ShouldProcess($move.Source, "Move to: $($move.Destination)")) {
        $parent = Split-Path -Parent $move.Destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Move-Item -LiteralPath $move.Source -Destination $move.Destination
        Write-Host ("Moved: {0} -> {1}" -f $move.Source, $move.Destination) -ForegroundColor Green
    }
}

if ($moves.Count -eq 0) {
    Write-Host 'No files need organizing.' -ForegroundColor Cyan
}
elseif ($WhatIfPreference) {
    Write-Host ("Preview complete: {0} file(s) would be moved. No files were changed." -f $moves.Count) -ForegroundColor Yellow
}
else {
    Write-Host ("Organization complete: moved {0} file(s)." -f $moves.Count) -ForegroundColor Cyan
}

if ($skipped -gt 0) {
    Write-Host ("Already organized: {0} file(s)." -f $skipped) -ForegroundColor DarkGray
}
if ($trackedSkipped -gt 0) {
    Write-Host ("Tracked files left unchanged: {0} file(s)." -f $trackedSkipped) -ForegroundColor DarkGray
}
