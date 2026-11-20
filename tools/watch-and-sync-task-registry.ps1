$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$downloadsPath = Join-Path $env:USERPROFILE 'Downloads'
$logDirectory = Join-Path $env:LOCALAPPDATA 'Personal-HQ'
$logPath = Join-Path $logDirectory 'sync-automation.log'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
function Write-RunLog([string]$message) {
    Add-Content -LiteralPath $logPath -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz') + ' ' + $message) -Encoding utf8
}
try {
    $exportFile = Get-ChildItem -LiteralPath $downloadsPath -Filter 'personal-hq-task-registry-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $exportFile) { return }
    $export = Get-Content -LiteralPath $exportFile.FullName -Raw | ConvertFrom-Json
    if ($export.registryStatus -ne 'current-user-export' -or -not $export.updatedAt) { return }
    if ($export.updatedAt -is [DateTimeOffset]) {
        $syncedAt = $export.updatedAt.ToUniversalTime()
    } elseif ($export.updatedAt -is [DateTime]) {
        $syncedAt = [DateTimeOffset]::new($export.updatedAt).ToUniversalTime()
    } else {
        $syncedAt = [DateTimeOffset]::Parse([string]$export.updatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
    }
    $age = [DateTimeOffset]::UtcNow - $syncedAt
    if ($age.TotalMinutes -lt -5 -or $age.TotalHours -gt 24) { return }
    $exportTimestamp = $syncedAt.ToString('o')
    $registryPath = Join-Path $repoRoot 'private\task-registry.json'
    if (Test-Path -LiteralPath $registryPath) {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        if ($registry.registryStatus -eq 'merged-desktop-task-update' -and $registry.updatedAt) {
            if ($registry.updatedAt -is [DateTimeOffset]) {
                $registryUpdatedAt = $registry.updatedAt.ToUniversalTime()
            } elseif ($registry.updatedAt -is [DateTime]) {
                $registryUpdatedAt = [DateTimeOffset]::new($registry.updatedAt).ToUniversalTime()
            } else {
                $registryUpdatedAt = [DateTimeOffset]::Parse([string]$registry.updatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
            }
            if ($syncedAt -le $registryUpdatedAt) { return }
        }
    }
    $markerPath = Join-Path $logDirectory 'last-synced-export.txt'
    if ((Test-Path -LiteralPath $markerPath) -and (Get-Content -LiteralPath $markerPath -Raw).Trim() -eq $exportTimestamp) { return }
    $helperPath = Join-Path $PSScriptRoot 'sync-task-registry.ps1'
    & $helperPath -ExportPath $exportFile.FullName *> $null
    if (-not $?) { throw 'sync helper failed' }
    Set-Content -LiteralPath $markerPath -Value $exportTimestamp -Encoding utf8
    Write-RunLog 'Fresh Personal HQ task export processed.'
} catch {
    Write-RunLog 'Sync attempt failed; run the sync helper interactively to review and resolve it.'
}
