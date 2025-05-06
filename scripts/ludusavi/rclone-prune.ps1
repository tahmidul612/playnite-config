<#
.SYNOPSIS
Prune Ludusavi game backups on a remote Rclone Google Drive folder.

.DESCRIPTION
This script iterates through each game folder under the specified remote root,
identifies 'full' and 'differential' backups by filename ('backup-YYYYMMDDThhmmssZ.zip'
vs. 'backup-…Z-diff.zip'), and deletes all but the newest N full backups
(and their M most recent diffs). If a folder contains only differential backups,
keeps the latest 14 diffs instead.

.PARAMETER RemoteRoot
The Rclone remote:path containing your Ludusavi backups, e.g. 'gdrive:ludusavi'.
Default: 'gdrive:ludusavi'

.PARAMETER KeepFulls
How many full backups to keep per game (must be ≥1).
Default: 2

.PARAMETER KeepDiffs
How many differential backups to keep for each kept full (≥0).
Default: 7

.PARAMETER DryRun
If specified, the script will only display which files 'would' be deleted,
without actually deleting anything.

.EXAMPLE
.\Prune-LudusaviBackups.ps1 -RemoteRoot 'gdrive:ludusavi' -KeepFulls 2 -KeepDiffs 7 -DryRun

.EXAMPLE
# Actually perform deletion (with confirmation prompts):
.\Prune-LudusaviBackups.ps1 -RemoteRoot 'gdrive:ludusavi' -KeepFulls 3 -KeepDiffs 5 -Confirm
Or:
.\Prune-LudusaviBackups.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string] $RemoteRoot = 'gdrive:ludusavi',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int] $KeepFulls = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 1000)]
    [int] $KeepDiffs = 7,

    [switch] $DryRun
)

<#
.SYNOPSIS
Prune backups within a single game folder.

.PARAMETER GameFolderPath
Remote path to the specific game folder (e.g. 'gdrive:ludusavi/MyGame').

.PARAMETER KeepFulls
Number of full backups to retain.

.PARAMETER KeepDiffs
Number of differential backups to retain per full backup.

.PARAMETER DryRun
If set, only report deletions, do not perform them.

.NOTES
Supports -WhatIf and -Confirm.
#>
function Invoke-PruneGameBackups {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $GameFolderPath,

        [Parameter(Mandatory = $true)]
        [int] $KeepFulls,

        [Parameter(Mandatory = $true)]
        [int] $KeepDiffs,

        [Parameter(Mandatory = $true)]
        [switch] $DryRun
    )

    $gameName = ($GameFolderPath -split '/')[ -1 ]
    Write-Verbose "Listing files in $GameFolderPath..."
    $items = rclone lsjson $GameFolderPath | ConvertFrom-Json

    # Only backup-*.zip files
    $backups = $items |
    Where-Object { -not $_.IsDir -and $_.Name -match '^backup-\d{8}T\d{6}Z(-diff)?\.zip$' }

    # Separate full vs diffs
    $fulls = @($backups | Where-Object { $_.Name -notmatch '-diff\.zip$' } | Sort-Object ModTime)
    $diffs = @($backups | Where-Object { $_.Name -match '-diff\.zip$' } | Sort-Object ModTime)

    # Prepare lists
    $toKeep = @()
    $toDelete = @()

    if ($fulls.Count -eq 0 -and $diffs.Count -gt 0) {
        # Only diffs present: keep latest 14
        $sortedDiffs = $diffs | Sort-Object ModTime
        $keepDiffsOnly = $sortedDiffs | Select-Object -Last 14
        $delDiffsOnly = $sortedDiffs | Where-Object { $keepDiffsOnly -notcontains $_ }

        $toKeep += $keepDiffsOnly
        $toDelete += $delDiffsOnly
    }
    else {
        # Standard case: fulls exist
        # 1. Full backups to keep/delete
        $keepFullsList = @($fulls | Select-Object -Last $KeepFulls)
        $delFulls = @($fulls | Where-Object { $keepFullsList -notcontains $_ })

        # 2. Differential backups to delete
        $delDiffs = @()
        if ($keepFullsList.Count -gt 0) {
            $sortedFulls = $keepFullsList | Sort-Object ModTime
            $oldestTime = $sortedFulls[0].ModTime

            # Diffs older than the oldest kept full
            $delDiffs += $diffs | Where-Object { $_.ModTime -lt $oldestTime }

            # For each kept full, keep only latest KeepDiffs diffs up to next full
            for ($i = 0; $i -lt $sortedFulls.Count; $i++) {
                $curFull = $sortedFulls[$i]
                if ($i -lt $sortedFulls.Count - 1) {
                    $nextFull = $sortedFulls[$i + 1]
                    $group = $diffs | Where-Object {
                        $_.ModTime -gt $curFull.ModTime -and $_.ModTime -lt $nextFull.ModTime
                    }
                }
                else {
                    $group = $diffs | Where-Object { $_.ModTime -gt $curFull.ModTime }
                }

                $keepGroup = @($group | Sort-Object ModTime | Select-Object -Last $KeepDiffs)
                $delDiffs += $group | Where-Object { $keepGroup -notcontains $_ }
            }
        }

        # Consolidate deletes
        $toDelete += $delFulls
        $toDelete += $delDiffs
        $toDelete = $toDelete | Sort-Object -Property Name -Unique

        # Build keep list: fulls + their diffs
        $toKeep += $keepFullsList
        if ($keepFullsList.Count -gt 0) {
            for ($i = 0; $i -lt $keepFullsList.Count; $i++) {
                $curFull = $keepFullsList[$i]
                if ($i -lt $keepFullsList.Count - 1) {
                    $nextFull = $keepFullsList[$i + 1]
                    $group = $diffs | Where-Object {
                        $_.ModTime -gt $curFull.ModTime -and $_.ModTime -lt $nextFull.ModTime
                    }
                }
                else {
                    $group = $diffs | Where-Object { $_.ModTime -gt $curFull.ModTime }
                }
                $keepGroup = @($group | Sort-Object ModTime | Select-Object -Last $KeepDiffs)
                $toKeep += $keepGroup
            }
        }
    }

    # Perform deletions (no inner progress bar)
    foreach ($file in $toDelete) {
        $remoteFile = "$GameFolderPath/$($file.Name)"
        if (-not $DryRun -and $PSCmdlet.ShouldProcess($remoteFile, 'Delete file')) {
            rclone delete $remoteFile | Out-Null
        }
    }

    # Return summary
    return [PSCustomObject]@{
        Game    = $gameName
        Kept    = $toKeep.Name
        Deleted = $toDelete.Name
    }
}

function Show-Tree {
    param(
        [string]   $Title,
        [string[]] $Kept,
        [string[]] $Deleted
    )
    Write-Host $Title
    Write-Host "├─ Kept ($($Kept.Count))"
    foreach ($n in $Kept) { Write-Host "│   └─ $n" }
    Write-Host "└─ Deleted ($($Deleted.Count))"
    foreach ($n in $Deleted) { Write-Host "    └─ $n" }
    Write-Host ''
}

#=== Main ===#
Write-Host "Fetching game folders from '$RemoteRoot'..."
$allEntries = rclone lsjson $RemoteRoot | ConvertFrom-Json
$gameFolders = $allEntries | Where-Object { $_.IsDir } | Select-Object -ExpandProperty Name
$totalGames = $gameFolders.Count

$summary = @()
for ($i = 0; $i -lt $totalGames; $i++) {
    $game = $gameFolders[$i]
    $outerPct = [math]::Round((($i + 1) / $totalGames) * 100, 0)

    Write-Progress -Activity 'Pruning backups' `
        -Status "[$($i + 1)/$totalGames] $game" `
        -PercentComplete $outerPct

    $path = "$RemoteRoot/$game"
    $summary += Invoke-PruneGameBackups `
        -GameFolderPath $path `
        -KeepFulls $KeepFulls `
        -KeepDiffs $KeepDiffs `
        -DryRun:$DryRun
}

Write-Progress -Activity 'Pruning backups' -Completed

# Print summary tree
Write-Host "`n=== Backup Prune Summary ===`n"
foreach ($entry in $summary) {
    Show-Tree -Title $entry.Game -Kept $entry.Kept -Deleted $entry.Deleted
}
