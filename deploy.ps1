$source = $PSScriptRoot
$addonName = "ProjEP_AH_Trader"
$target = "C:\Ascension\Launcher\resources\epoch-live\Interface\AddOns\$addonName"

$extensions = @("*.lua", "*.toc", "*.xml")
$exclude    = @("deploy.ps1")

New-Item -ItemType Directory -Path $target -Force | Out-Null

$files = $extensions | ForEach-Object { Get-ChildItem -Path $source -Filter $_ } | Where-Object { $_.Name -notin $exclude }

foreach ($file in $files) {
    Copy-Item -Path $file.FullName -Destination $target -Force
}

$count = ($files | Measure-Object).Count
Write-Host "[$addonName] $count Dateien nach '$target' deployt." -ForegroundColor Green
