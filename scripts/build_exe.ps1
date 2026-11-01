<#
.SYNOPSIS
    构建深清（身轻）Windows 发行包。
.DESCRIPTION
    onedir：产出 dist\深清\ 目录并压缩为 dist\深清_绿色版.zip
    onefile：产出 dist\深清.exe 单文件
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build_exe.ps1 -Mode onedir
#>
param(
    [ValidateSet("onedir", "onefile")]
    [string]$Mode = "onedir"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[1/3] 检查依赖 ..."
python -m pip install --upgrade pyinstaller

Write-Host "[2/3] 打包（$Mode）..."
if ($Mode -eq "onefile") {
    $env:SHENQING_ONEFILE = "1"
} else {
    Remove-Item Env:SHENQING_ONEFILE -ErrorAction SilentlyContinue
}
python -m PyInstaller --noconfirm --clean --workpath "build/pyinstaller" --distpath "dist" "packaging/ShenQing.spec"

Write-Host "[3/3] 收尾 ..."
if ($Mode -eq "onedir") {
    $zip = "dist/深清_绿色版.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path "dist/深清" -DestinationPath $zip -Force
    Write-Host "完成：dist\深清\ 以及 dist\深清_绿色版.zip"
} else {
    Write-Host "完成：dist\深清.exe"
}
