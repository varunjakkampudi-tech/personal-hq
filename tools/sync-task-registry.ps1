[CmdletBinding()]
param(
    [string]$ExportPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$registryRelativePath = 'private/task-registry.json'
$registryPath = Join-Path $repoRoot $registryRelativePath

if (-not $ExportPath) {
    $downloadsPath = Join-Path $env:USERPROFILE 'Downloads'
    $latestExport = Get-ChildItem -LiteralPath $downloadsPath -Filter 'personal-hq-task-registry-*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestExport) {
        throw "No Personal HQ task export was found in $downloadsPath. Use Sync tasks in the dashboard first."
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
    throw 'This export is not marked as a current dashboard export. Use the dashboard Sync tasks button.'
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
$sameData = $false
if ($existingJson) {
    $existing = $existingJson | ConvertFrom-Json
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
    $sameData = (($existing.data | ConvertTo-Json -Depth 50 -Compress) -eq ($export.data | ConvertTo-Json -Depth 50 -Compress))
}
if ($sameData) {
    Write-Output 'Task registry data already matches this export; no update was needed.'
    exit 0
}

$backupDirectory = Join-Path $env:LOCALAPPDATA 'Personal-HQ\registry-backups'
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
if ($existingJson) {
    $backupName = 'task-registry-before-sync-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json'
    Set-Content -LiteralPath (Join-Path $backupDirectory $backupName) -Value $existingJson -Encoding utf8
}

New-Item -ItemType Directory -Path (Split-Path -Parent $registryPath) -Force | Out-Null
Set-Content -LiteralPath $registryPath -Value $allJson -Encoding utf8

git -C $repoRoot add -- $registryRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the task registry.' }

$commitMessage = 'Sync task registry ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
git -C $repoRoot commit --only -m $commitMessage -- $registryRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not commit the task registry.' }

git -C $repoRoot push origin main
if ($LASTEXITCODE -ne 0) { throw 'The local registry commit succeeded, but pushing to GitHub failed.' }

Write-Output ("Synced " + $export.data.tasks.Count + " tasks to the public Personal HQ repository.")
