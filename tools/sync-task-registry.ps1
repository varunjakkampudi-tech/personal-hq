[CmdletBinding()]
param(
    [string]$ExportPath,
    [switch]$PublishMergedRegistry
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$registryRelativePath = 'private/task-registry.json'
$registryPath = Join-Path $repoRoot $registryRelativePath
$publicTasksRelativePath = 'life-system/tasks.json'
$publicTasksPath = Join-Path $repoRoot $publicTasksRelativePath
$publicSeedRelativePath = 'life-system/data.js'
$publicSeedPath = Join-Path $repoRoot $publicSeedRelativePath
$publicIndexRelativePath = 'life-system/index.html'
$publicIndexPath = Join-Path $repoRoot $publicIndexRelativePath
$publicHistoryRelativePath = 'life-system/history.json'
$publicHistoryPath = Join-Path $repoRoot $publicHistoryRelativePath

if ($PublishMergedRegistry) {
    if ($ExportPath) { throw 'Use either -PublishMergedRegistry or -ExportPath, not both.' }
    if (-not (Test-Path -LiteralPath $registryPath)) { throw 'The private task registry was not found.' }
    $export = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    if ($export.registryStatus -ne 'merged-desktop-task-update') {
        throw 'The private registry is not marked as merged-desktop-task-update. Use the normal fresh-export sync path.'
    }
    if (-not $export.dashboardExportUpdatedAt) {
        throw 'The private registry has no recorded full dashboard export timestamp; refusing to publish merged status.'
    }
} else {
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
}
if ($export.version -ne 1 -or -not $export.data -or -not ($export.data.tasks -is [System.Array])) {
    throw 'The selected file is not a supported Personal HQ export.'
}
if (-not $PublishMergedRegistry -and $export.registryStatus -ne 'current-user-export') {
    throw 'This export is not marked as a current dashboard export. Use the dashboard Export tasks button.'
}
if (-not $export.updatedAt) {
    throw 'The export has no verified sync timestamp.'
}

if ($export.updatedAt -is [DateTimeOffset]) {
    $syncedAt = $export.updatedAt.ToUniversalTime()
} elseif ($export.updatedAt -is [DateTime]) {
    $syncedAt = [DateTimeOffset]::new($export.updatedAt).ToUniversalTime()
} else {
    $syncedAt = [DateTimeOffset]::Parse([string]$export.updatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
}
$age = [DateTimeOffset]::UtcNow - $syncedAt
if ($age.TotalMinutes -lt -5 -or (-not $PublishMergedRegistry -and $age.TotalHours -gt 24)) {
    throw 'The dashboard export timestamp is in the future or older than 24 hours. Create a fresh export.'
}
if (-not $PublishMergedRegistry -and (Test-Path -LiteralPath $registryPath)) {
    $currentRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    if ($currentRegistry.registryStatus -eq 'merged-desktop-task-update' -and $currentRegistry.updatedAt) {
        if ($currentRegistry.updatedAt -is [DateTimeOffset]) {
            $registryUpdatedAt = $currentRegistry.updatedAt.ToUniversalTime()
        } elseif ($currentRegistry.updatedAt -is [DateTime]) {
            $registryUpdatedAt = [DateTimeOffset]::new($currentRegistry.updatedAt).ToUniversalTime()
        } else {
            $registryUpdatedAt = [DateTimeOffset]::Parse([string]$currentRegistry.updatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
        }
        if ($syncedAt -le $registryUpdatedAt) {
            throw 'This dashboard export predates the latest merged task registry. Create a fresh export before syncing so newer task updates are preserved.'
        }
    }
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

# Public task refreshes contain no private notes. Preserve existing registry notes
# for imported fields unless the dashboard editor explicitly confirmed clearing them.
$existingNotesByTaskId = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
if (Test-Path -LiteralPath $registryPath) {
    $existingRegistryForNotes = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    foreach ($existingTaskForNotes in $existingRegistryForNotes.data.tasks) {
        $existingNote = [string]$existingTaskForNotes.notes
        if ($existingTaskForNotes.id -and -not [string]::IsNullOrWhiteSpace($existingNote)) {
            $existingNotesByTaskId[[string]$existingTaskForNotes.id] = $existingNote
        }
    }
}
foreach ($task in $export.data.tasks) {
    $clearNotesProperty = $task.PSObject.Properties['clearNotes']
    $clearNotesConfirmed = $null -ne $clearNotesProperty -and [bool]$clearNotesProperty.Value
    $preservePrivateProperty = $task.PSObject.Properties['preservePrivateNotes']
    $preservePrivateNotes = $null -ne $preservePrivateProperty -and [bool]$preservePrivateProperty.Value
    $taskId = [string]$task.id
    if (-not $clearNotesConfirmed -and $existingNotesByTaskId.ContainsKey($taskId)) {
        $existingPrivateNote = $existingNotesByTaskId[$taskId]
        $incomingNote = [string]$task.notes
        $mergedNote = $null
        if ([string]::IsNullOrWhiteSpace($incomingNote)) {
            $mergedNote = $existingPrivateNote
        } elseif ($preservePrivateNotes) {
            if ($existingPrivateNote.Contains($incomingNote, [System.StringComparison]::Ordinal)) {
                $mergedNote = $existingPrivateNote
            } else {
                $mergedNote = $existingPrivateNote + [Environment]::NewLine + [Environment]::NewLine + $incomingNote
            }
        }
        if ($null -ne $mergedNote) {
            $notesProperty = $task.PSObject.Properties['notes']
            if ($null -eq $notesProperty) {
                $task | Add-Member -NotePropertyName notes -NotePropertyValue $mergedNote
            } else {
                $task.notes = $mergedNote
            }
        }
    }
    if ($null -ne $clearNotesProperty) { $task.PSObject.Properties.Remove('clearNotes') }
    if ($null -ne $preservePrivateProperty) { $task.PSObject.Properties.Remove('preservePrivateNotes') }
}

$restrictedDataPattern = '(?<!\d)\d{12}(?!\d)|\b[A-Z]{5}\d{4}[A-Z]\b|\b[A-Z0-9]{15}\b|(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b|(?<!\d)(?:\+?91[- .]?)?[6-9]\d{9}(?!\d)'
if (-not $PublishMergedRegistry) {
    $export.dashboardExportUpdatedAt = $export.updatedAt
}
$allJson = $export | ConvertTo-Json -Depth 50

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
$historySource = @()
if (Test-Path -LiteralPath $publicHistoryPath) {
    $historyDocument = Get-Content -LiteralPath $publicHistoryPath -Raw | ConvertFrom-Json
    if ($historyDocument.events -is [System.Array]) { $historySource = @($historyDocument.events) }
} elseif (Test-Path -LiteralPath $publicTasksPath) {
    $existingPublicSnapshot = Get-Content -LiteralPath $publicTasksPath -Raw | ConvertFrom-Json
    if ($existingPublicSnapshot.history -is [System.Array]) { $historySource = @($existingPublicSnapshot.history) }
}
$publicHistory = @(
    foreach ($event in $historySource) {
        if (-not $event.date -or -not $event.area -or -not $event.title -or -not $event.status) { continue }
        [ordered]@{
            date = [string]$event.date
            area = [string]$event.area
            title = [string]$event.title
            status = [string]$event.status
        }
    }
)
$publicAreas = @($export.data.areas | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if ($publicAreas.Count -eq 0) {
    $publicAreas = @($publicTasks | ForEach-Object { $_.area } | Sort-Object -Unique)
}
$publicSnapshot = [ordered]@{
    schemaVersion = 1
    generatedAt = $export.updatedAt
    sourceSnapshotStatus = if ($PublishMergedRegistry) { 'merged-desktop-task-update' } else { 'current-user-export' }
    sourceSnapshotUpdatedAt = $export.updatedAt
    dashboardExportUpdatedAt = if ($PublishMergedRegistry) { $export.dashboardExportUpdatedAt } else { $export.updatedAt }
    description = 'Public task snapshot. Personal notes and dashboard habit logs are not included.'
    areas = $publicAreas
    tasks = $publicTasks
    history = $publicHistory
}
$publicTasksJson = $publicSnapshot | ConvertTo-Json -Depth 20
if ($publicTasksJson -match $restrictedDataPattern) {
    throw 'The public task snapshot appears to contain a government identifier, GSTIN, email address or phone number. Remove sensitive details before publishing.'
}
$publicSeedContent = 'window.PERSONAL_HQ_SEED = ' + $publicTasksJson.Trim() + ';'
$publicIndexContent = Get-Content -LiteralPath $publicIndexPath -Raw
$seedVersion = $syncedAt.ToString('yyyyMMddHHmmss')
$seedScriptPattern = '<script src="data\.js(?:\?v=[^"]*)?"></script>'
if ($publicIndexContent -notmatch $seedScriptPattern) {
    throw 'Could not find the expected task-seed script reference in life-system/index.html.'
}
$publicIndexContent = [regex]::Replace($publicIndexContent, $seedScriptPattern, ('<script src="data.js?v=' + $seedVersion + '"></script>'), 1)
$publicHistoryDocument = [ordered]@{
    description = 'Public milestone summaries. Supporting evidence and private details are omitted.'
    events = $publicHistory
}
$publicHistoryJson = $publicHistoryDocument | ConvertTo-Json -Depth 20

function Sync-PagesTaskFeed {
    $pagesRoot = Join-Path (Split-Path -Parent $repoRoot) 'Personal-HQ-Pages'
    if (-not (Test-Path -LiteralPath (Join-Path $pagesRoot '.git'))) { throw "The Personal HQ Pages repository was not found at $pagesRoot." }
    $pagesRemote = (& git -C $pagesRoot remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or $pagesRemote -notmatch '^https://github\.com/varunjakkampudi-tech/personal-hq-pages\.git$') { throw 'The Pages origin is not the expected public Personal HQ Pages repository.' }
    $pagesBranch = (& git -C $pagesRoot branch --show-current)
    if ($LASTEXITCODE -ne 0 -or $pagesBranch -ne 'main') { throw "Expected Pages branch main; found '$pagesBranch'." }
    git -C $pagesRoot fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the Pages branch before syncing its task feed.' }
    $tracking = (& git -C $pagesRoot rev-list --left-right --count origin/main...HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Could not compare the Pages branch with origin/main.' }
    $counts = @($tracking -split '\s+' | Where-Object { $_ -ne '' })
    if ($counts.Count -ne 2) { throw 'Could not parse the Pages branch tracking counts.' }
    $behind = [int]$counts[0]
    $ahead = [int]$counts[1]
    if ($behind -gt 0) { throw 'The Pages branch is behind origin/main. Review and update it before mirroring task data.' }
    if ($ahead -gt 0) {
        $subject = (& git -C $pagesRoot log -1 --format=%s)
        $paths = @(& git -C $pagesRoot diff-tree --no-commit-id --name-only -r HEAD)
        $allowed = @('life-system/tasks.json', 'life-system/data.js', 'life-system/history.json', 'life-system/index.html')
        if ($LASTEXITCODE -ne 0 -or $ahead -ne 1 -or $subject -notmatch '^Sync task feed \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' -or @($paths | Where-Object { $_ -notin $allowed }).Count -gt 0 -or $paths.Count -eq 0) { throw 'The Pages branch has unpublished commits outside a single task-feed update. Review it before syncing.' }
        $status = @(& git -C $pagesRoot status --porcelain --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) { throw 'The Pages branch has uncommitted changes. Review them before retrying the task-feed push.' }
        git -C $pagesRoot push origin main
        if ($LASTEXITCODE -ne 0) { throw 'The Pages task-feed commit is ready, but pushing it failed.' }
        Write-Output 'Pushed the pending sanitized task feed to the Pages repository.'
    }
    $status = @(& git -C $pagesRoot status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) { throw 'The Pages repository has local changes. Review them before mirroring task data.' }
    Copy-Item -LiteralPath $publicTasksPath -Destination (Join-Path $pagesRoot 'life-system/tasks.json') -Force
    Copy-Item -LiteralPath $publicSeedPath -Destination (Join-Path $pagesRoot 'life-system/data.js') -Force
    Copy-Item -LiteralPath $publicHistoryPath -Destination (Join-Path $pagesRoot 'life-system/history.json') -Force
    Copy-Item -LiteralPath $publicIndexPath -Destination (Join-Path $pagesRoot 'life-system/index.html') -Force
    git -C $pagesRoot add -- 'life-system/tasks.json' 'life-system/data.js' 'life-system/history.json' 'life-system/index.html'
    if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the sanitized task feed in the Pages repository.' }
    $staged = @(& git -C $pagesRoot diff --cached --name-only)
    if ($LASTEXITCODE -ne 0 -or @($staged | Where-Object { $_ -notin @('life-system/tasks.json', 'life-system/data.js', 'life-system/history.json', 'life-system/index.html') }).Count -gt 0) { throw 'The Pages index contains paths outside the sanitized task feed; refusing to commit.' }
    if ($staged.Count -eq 0) { Write-Output 'The sanitized task feed already matches the Pages repository.'; return }
    git -C $pagesRoot commit --only -m ('Sync task feed ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -- 'life-system/tasks.json' 'life-system/data.js' 'life-system/history.json' 'life-system/index.html'
    if ($LASTEXITCODE -ne 0) { throw 'Git could not commit the sanitized task feed in the Pages repository.' }
    git -C $pagesRoot push origin main
    if ($LASTEXITCODE -ne 0) { throw 'The Pages task-feed commit succeeded locally, but pushing it failed.' }
    Write-Output 'Synced the sanitized task feed to the public Pages repository.'
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
$registryChanged = -not $PublishMergedRegistry
if ($PublishMergedRegistry) {
    if (-not $existingJson) { throw 'The private task registry was not found while preparing merged publication.' }
    $existing = $existingJson | ConvertFrom-Json
    $registryChanged = $false
} elseif ($existingJson) {
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
$samePublicIndex = (Get-Content -LiteralPath $publicIndexPath -Raw) -eq $publicIndexContent
$samePublicHistory = (Test-Path -LiteralPath $publicHistoryPath) -and ((Get-Content -LiteralPath $publicHistoryPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress) -eq ($publicHistoryDocument | ConvertTo-Json -Depth 20 -Compress))
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
if (-not $samePublicHistory) { Set-Content -LiteralPath $publicHistoryPath -Value $publicHistoryJson -Encoding utf8 }
if (-not $samePublicIndex) { Set-Content -LiteralPath $publicIndexPath -Value $publicIndexContent -Encoding utf8 }

if ($samePublicTasks -and $samePublicSeed -and $samePublicHistory -and $samePublicIndex) {
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
    Sync-PagesTaskFeed
    if ($PublishMergedRegistry) { Write-Output 'The sanitized public task feed already matches the merged private registry.' }
    else { Write-Output 'The sanitized public task feed already matches this export.' }
    return
}

git -C $repoRoot add -- $publicTasksRelativePath $publicSeedRelativePath $publicHistoryRelativePath $publicIndexRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not stage the sanitized public task feed.' }

$commitMessage = 'Sync task registry ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
git -C $repoRoot commit --only -m $commitMessage -- $publicTasksRelativePath $publicSeedRelativePath $publicHistoryRelativePath $publicIndexRelativePath
if ($LASTEXITCODE -ne 0) { throw 'Git could not commit the sanitized public task feed.' }

git -C $repoRoot push origin main
if ($LASTEXITCODE -ne 0) { throw 'The local registry commit succeeded, but pushing to GitHub failed.' }
Sync-PagesTaskFeed

if ($PublishMergedRegistry) {
    Write-Output ("Published the sanitized merged registry projection for " + $export.data.tasks.Count + " tasks; the full dashboard export timestamp was preserved.")
} else {
    Write-Output ("Synced " + $export.data.tasks.Count + " tasks to the public Personal HQ repository.")
}
