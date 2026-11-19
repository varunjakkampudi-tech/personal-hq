[CmdletBinding()]
param(
    [string]$ExportPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$registryRelativePath = 'private/task-registry.json'
$registryPath = Join-Path $repoRoot $registryRelativePath
$publicTasksRelativePath = 'life-system/tasks.json'
$publicTasksPath = Join-Path $repoRoot $publicTasksRelativePath
$publicSeedRelativePath = 'life-system/data.js'
$publicSeedPath = Join-Path $repoRoot $publicSeedRelativePath

if (-not $ExportPath) {
    $downloadsPath = Join-Path $env:USERPROFILE 'Downloads'
    $latestExport = Get-ChildItem -LiteralPath $downloadsPath -Filter 'personal-hq-task-registry-*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestExport) {
        throw "No Personal HQ task export was found in $downloadsPath. Use Export tasks in the dashboard first."
    }
    $ExportPath = $latestExport.FullName
}

$sourcePath = (Resolve-Path -LiteralPath $ExportPath).Path
if ($sourcePath -eq $registryPath) {
    throw 'Choose the downloaded dashboard export, not the registry destination.'
}

$export = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
if ($export.version -ne 1 -or -not $export.data -or -not ($export.data.tasks -is [System.Array])) {
    throw 'The selected file is not a supported Personal HQ export.'
}
if ($export.registryStatus -ne 'current-user-export') {
    throw 'This export is not marked as a current dashboard export. Use the dashboard Export tasks button.'
}
if (-not $export.updatedAt) {
    throw 'The export has no verified sync timestamp.'
}

$syncedAt = [DateTimeOffset]::Parse($export.updatedAt).ToUniversalTime()
$age = [DateTimeOffset]::UtcNow - $syncedAt
if ($age.TotalMinutes -lt -5 -or $age.TotalHours -gt 24) {
    throw 'The dashboard export timestamp is in the future or older than 24 hours. Create a fresh export.'
}
if ($export.data.tasks.Count -eq 0) {
    throw 'The export contains no tasks; refusing to replace the existing registry with an empty task list.'
}
$validStatuses = @('Not started', 'In progress', 'Waiting', 'Done')
$seenTaskIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($task in $export.data.tasks) {
    if (-not $task.id -or -not $task.title -or -not $task.area) {
        throw 'Every task must have an id, title and area.'
    }
    if ($task.status -notin $validStatuses) {
        throw "Task '$($task.title)' has an unsupported status."
    }
    if (-not $seenTaskIds.Add([string]$task.id)) {
        throw "Duplicate task id '$($task.id)' found in the export."
    }
}

$allJson = $export | ConvertTo-Json -Depth 50
if ($allJson -match '(?<!\d)\d{12}(?!\d)' -or $allJson -match '\b[A-Z]{5}\d{4}[A-Z]\b' -or $allJson -match '\b[A-Z0-9]{15}\b' -or $allJson -match '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b' -or $allJson -match '(?<!\d)(?:\+?91[- .]?)?[6-9]\d{9}(?!\d)') {
    throw 'The export appears to contain a government identifier, GSTIN, email address or phone number. Remove sensitive details before syncing to this public repository.'
}

$publicTasks = @(
    foreach ($task in $export.data.tasks) {
        [ordered]@{
            id = [string]$task.id
            title = [string]$task.title
            area = [string]$task.area
            due = if ($task.due) { [string]$task.due } else { '' }
            status = [string]$task.status
            nextAction = if ($task.nextAction) { [string]$task.nextAction } else { [string]$task.title }
        }
    }
)
$publicHistory = @()
if (Test-Path -LiteralPath $publicTasksPath) {
    $existingPublicSnapshot = Get-Content -LiteralPath $publicTasksPath -Raw | ConvertFrom-Json
    if ($existingPublicSnapshot.history -is [System.Array]) {
        $publicHistory = @($existingPublicSnapshot.history)
    }
}
$publicAreas = @($export.data.areas | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if ($publicAreas.Count -eq 0) {
    $publicAreas = @($publicTasks | ForEach-Object { $_.area } | Sort-Object -Unique)
}
$publicSnapshot = [ordered]@{
    schemaVersion = 1
    generatedAt = $export.updatedAt
    sourceSnapshotStatus = 'current-user-export'
    sourceSnapshotUpdatedAt = $export.updatedAt
    description = 'Public task snapshot. Personal notes and dashboard habit logs are not included.'
    areas = $publicAreas
    tasks = $publicTasks
    history = $publicHistory
}
$publicTasksJson = $publicSnapshot | ConvertTo-Json -Depth 20
$publicSeedContent = 'window.PERSONAL_HQ_SEED = ' + $publicTasksJson.Trim() + ';'

$remoteUrl = (& git -C $repoRoot remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0 -or $remoteUrl -notmatch '^https://github\.com/varunjakkampudi-tech/personal-hq\.git$') {
    throw 'The origin remote is not the expected public Personal HQ GitHub repository.'
}

$branch = (& git -C $repoRoot branch --show-current)
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
    throw "Expected branch main; found '$branch'."
}

$existingJson = if (Test-Path -LiteralPath $registryPath) {
    Get-Content -LiteralPath $registryPath -Raw
} else {
    $null
}
$registryChanged = $true
if ($existingJson) {
    $existing = $existingJson | ConvertFrom-Json
    $registryChanged = ($existing | ConvertTo-Json -Depth 50 -Compress) -ne ($export | ConvertTo-Json -Depth 50 -Compress)
    $incomingTaskIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($task in $export.data.tasks) {
        [void]$incomingTaskIds.Add([string]$task.id)
    }
    $missingExistingTaskCount = 0
    foreach ($existingTask in $existing.data.tasks) {
        if (-not $incomingTaskIds.Contains([string]$existingTask.id)) {
            $missingExistingTaskCount++
        }
    }
    if ($missingExistingTaskCount -gt 0) {
        throw "The export omits $missingExistingTaskCount task(s) already in the registry. Refusing to replace the full snapshot. Restore a complete dashboard backup before syncing."
    }
}
$samePublicTasks = (Test-Path -LiteralPath $publicTasksPath) -and ((Get-Content -LiteralPath $publicTasksPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress) -eq ($publicSnapshot | ConvertTo-Json -Depth 20 -Compress))
$samePublicSeed = (Test-Path -LiteralPath $publicSeedPath) -and ((Get-Content -LiteralPath $publicSeedPath -Raw).Trim() -eq $publicSeedContent)
$backupDirectory = Join-Path $env:LOCALAPPDATA 'Personal-HQ\registry-backups'
if ($registryChanged -and $existingJson) {
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $backupName = 'task-registry-before-sync-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'
    Set-Content -LiteralPath (Join-Path $backupDirectory $backupName) -Value $existingJson -Encoding utf8
}

New-Item -ItemType Directory -Path (Split-Path -Parent $registryPath) -Force | Out-Null
if ($registryChanged) { Set-Content -LiteralPath $registryPath -Value $allJson -Encoding utf8 }
if (-not $samePublicTasks) { Set-Content -LiteralPath $publicTasksPath -Value $publicTasksJson -Encoding utf8 }
if (-not $samePublicSeed) { Set-Content -LiteralPath $publicSeedPath -Value $publicSeedContent -Encoding utf8 }

if ($samePublicTasks -and $samePublicSeed) {
    $trackingCounts = (& git -C $repoRoot rev-list --left-right --count origin/main...HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Could not compare local main with origin/main before deciding whether to push.' }
    $counts = @($trackingCounts -split '\s+' | Where-Object { $_ -ne '' })
    if ($counts.Count -ne 2) { throw 'Could not parse the local and remote commit counts.' }
    $behindCount = [int]$counts[0]
    $aheadCount = [int]$counts[1]
    if ($behindCount -gt 0) { throw 'The public feed matches this export, but local main is behind origin/main. Review and update the branch before syncing.' }
    if ([int]$aheadCount -gt 0) {
        $pendingSubject = (& git -C $repoRoot log -1 --format=%s)
        if ($LASTEXITCODE -ne 0 -or [int]$aheadCount -ne 1 -or $pendingSubject -notmatch '^Sync task registry \d{4}-\d{2}-\d{2} \d{2}:\d{2}$') {
            throw 'The public feed matches this export, but main has commits that are not a single pending task-sync commit. Review the branch before pushing.'
        }
        git -C $repoRoot push origin main
        if ($LASTEXITCODE -ne 0) { throw 'The task-sync commit is ready, but pushing it to GitHub failed.' }
    }
    Write-Output 'The sanitized public task feed already matches this export.'
    return
}

git -C $repoRoot add -- $publicTasksRelativePath $publicSeedRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the sanitized public task feed.' }

$commitMessage = 'Sync task registry ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
git -C $repoRoot commit --only -m $commitMessage -- $publicTasksRelativePath $publicSeedRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not commit the sanitized public task feed.' }

git -C $repoRoot push origin main
if ($LASTEXITCODE -ne 0) { throw 'The local registry commit succeeded, but pushing to GitHub failed.' }

Write-Output ("Synced " + $export.data.tasks.Count + " tasks to the public Personal HQ repository.")
