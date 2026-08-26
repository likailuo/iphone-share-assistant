# 打包辅助脚本（UTF-8 BOM）：由 打包.bat 调用。
# 作用：检查/安装 PS2EXE，并把单文件 源码/主程序-3.0.ps1 打包为无控制台、需管理员权限的独立 GUI EXE。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }

$inputFile  = Join-Path $root '源码\主程序-3.0.ps1'
$iconFile   = Join-Path $root '资源\222.ico'

foreach ($p in @($inputFile, $iconFile)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "[错误] 缺少打包所需文件：$p"
        exit 1
    }
}
$existingVersions = @(Get-ChildItem -LiteralPath (Join-Path $root '打包输出') -Filter 'iPhone共享助手-*.exe' -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.BaseName -match 'iPhone共享助手-(\d+\.\d+)$') { [version]$matches[1] }
    })
$currentVersion = if ($existingVersions.Count -gt 0) { ($existingVersions | Sort-Object | Select-Object -Last 1) } else { [version]'3.5' }
$nextVersion = [version]::new($currentVersion.Major, $currentVersion.Minor + 1)
$versionText = $nextVersion.ToString(2)
$outputFile = Join-Path $root "打包输出\iPhone共享助手-$versionText.exe"
$outDir = Split-Path -Parent $outputFile
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if (-not (Get-Module -ListAvailable ps2exe)) {
    Write-Host '未检测到 PS2EXE，正在尝试安装...'
    try {
        Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
    } catch {
        Write-Host "[错误] PS2EXE 安装失败：$($_.Exception.Message)"
        exit 1
    }
}

Write-Host "正在打包 iPhone 共享助手 $versionText..."
Invoke-ps2exe -inputFile $inputFile -outputFile $outputFile -iconFile $iconFile -noConsole -requireAdmin -title "iPhone 共享助手 $versionText" -description 'iPhone SMB 文件共享助手' -version "$($nextVersion.Major).$($nextVersion.Minor).0.0"

if (Test-Path -LiteralPath $outputFile) {
    $item = Get-Item -LiteralPath $outputFile
    Write-Host "打包成功：$($item.FullName)"
    Write-Host ("文件大小：{0:N1} KB" -f ($item.Length / 1KB))
} else {
    Write-Host '[错误] 未找到打包生成的 EXE 文件。'
    exit 1
}
