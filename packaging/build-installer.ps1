[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0',
    [string]$ISCCPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDir = $PSScriptRoot
$payloadDir = Join-Path $projectDir 'dist\payload'

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  BDSplayer 正式版安装包构建程序 v$Version" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Locate ISCC.exe
if (-not $ISCCPath) {
    $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($compiler) { $ISCCPath = $compiler.Source }
    foreach ($candidate in @(
        "C:\Users\gray9\AppData\Local\Temp\sakuraplayer-task319-inno\Inno\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\InnoSetup\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )) {
        if (-not $ISCCPath -and (Test-Path -LiteralPath $candidate)) { $ISCCPath = $candidate }
    }
}
if (-not $ISCCPath -or -not (Test-Path -LiteralPath $ISCCPath)) {
    throw '未找到 Inno Setup 6+ 编译器。请先安装或通过 -ISCCPath 参数指定 ISCC.exe。'
}
Write-Host "Inno Setup 编译器: $ISCCPath" -ForegroundColor Green

# 2. Strict Security & Cleanliness Audit
Write-Host "`n[安全与隐私审计] 检查 Payload 是否包含敏感凭证..." -ForegroundColor Yellow
$leakFiles = Get-ChildItem -Path $payloadDir -Recurse | Where-Object {
    $_.Name -match '\.db$|token|cookie|auth|history|secret|\.key$' -and $_.Name -notmatch 'NativeAssetsManifest'
}
if ($leakFiles) {
    Write-Host "【严重警告】检测到潜在的凭证或历史记录文件，构建已紧急终止：" -ForegroundColor Red
    $leakFiles | ForEach-Object { Write-Host " - $($_.FullName)" -ForegroundColor Red }
    throw "Payload 安全审计失败：禁止打包任何个人登录凭据或数据库文件。"
}
Write-Host "[安全审计通过] Payload 无任何凭证或数据库文件残留，状态为绝对纯净。" -ForegroundColor Green

# 3. Compile Installer with Inno Setup
Write-Host "`n[开始打包] 正在通过 Inno Setup 编译 BDSplayer 安装程序..." -ForegroundColor Yellow
$issPath = Join-Path $projectDir 'bdsplayer.iss'
& $ISCCPath "/DMyAppVersion=$Version" $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup 编译失败，退出码：$LASTEXITCODE"
}

# 4. Generate Checksum
$installer = Join-Path $projectDir "dist\BDSplayer-v$Version-x64-Setup.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    throw "未找到生成的安装程序：$installer"
}
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($installer))" | Set-Content -LiteralPath "$installer.sha256" -Encoding ASCII

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "  打包成功！" -ForegroundColor Green
Write-Host "  安装程序: $installer" -ForegroundColor White
Write-Host "  大小: $([math]::Round((Get-Item $installer).Length / 1MB, 2)) MB" -ForegroundColor White
Write-Host "  SHA256: $hash" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Green
