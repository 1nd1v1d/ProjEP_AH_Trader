$source     = $PSScriptRoot
$addonName  = "ProjEP_AH_Trader"
$target     = "C:\Ascension\Launcher\resources\epoch-live\Interface\AddOns\$addonName"
$extensions = @("*.lua", "*.toc", "*.xml")
$exclude    = @("deploy.ps1", "watch.ps1")

New-Item -ItemType Directory -Path $target -Force | Out-Null

function Deploy {
    $files = $extensions | ForEach-Object { Get-ChildItem -Path $source -Filter $_ } |
             Where-Object { $_.Name -notin $exclude }
    foreach ($file in $files) {
        Copy-Item -Path $file.FullName -Destination $target -Force
    }
    $count = ($files | Measure-Object).Count
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $count Dateien deployt nach '$target'" -ForegroundColor Green
}

# Initialer Deploy
Deploy

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path   = $source
$watcher.Filter = "*.*"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName
$watcher.EnableRaisingEvents = $true

$action = {
    $name = $Event.SourceEventArgs.Name
    $ext  = [System.IO.Path]::GetExtension($name).ToLower()
    if ($ext -in @(".lua", ".toc", ".xml")) {
        $ts = Get-Date -Format "HH:mm:ss"
        Write-Host "[$ts] Geaendert: $name – deploye..." -ForegroundColor Yellow
        & "$PSScriptRoot\deploy.ps1"
    }
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

Write-Host "Watching '$source' fuer .lua/.toc/.xml Aenderungen... (Ctrl+C zum Beenden)" -ForegroundColor Cyan

try {
    while ($true) {
        Start-Sleep -Seconds 1
        # Ausstehende Events verarbeiten
        [System.Windows.Forms.Application]::DoEvents() 2>$null
    }
} finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
}
