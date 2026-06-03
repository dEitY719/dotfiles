<#
.SYNOPSIS
    WSL2 ext4.vhdx 압축 + (선택) Windows 디스크 정리 스크립트

.DESCRIPTION
    1) 대상 배포판의 vhdx 경로를 레지스트리에서 자동 탐색
    2) shutdown 전 WSL 내부에서 fstrim 실행 (회수량 극대화)
    3) wsl --shutdown 후 diskpart로 compact vdisk (또는 -UseSparse 모드 전환)
    4) (선택) Windows Update 캐시 / TEMP / Chrome 캐시 정리 + cleanmgr GUI

.PARAMETER DistroName
    대상 WSL 배포판 이름. 기본값 "Ubuntu-24.04". (wsl -l -v 로 확인 가능)

.PARAMETER UseSparse
    일회성 compact 대신, 앞으로 자동으로 줄어드는 sparse 모드로 전환.
    (최신 WSL 빌드 필요)

.PARAMETER SkipWindowsClean
    Windows 쪽 정리 단계를 건너뜀.

.EXAMPLE
    # 파일 저장 없이 원격에서 직접 실행 (관리자 PowerShell):
    iex (irm 'https://raw.githubusercontent.com/dEitY719/dotfiles/main/windows/Compact-WSL.ps1')

    # 일반 PowerShell에서 (자동 권한 상승 포함):
    powershell -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/dEitY719/dotfiles/main/windows/Compact-WSL.ps1')"

    # 파일로 저장 후 실행:
    .\Compact-WSL.ps1
    .\Compact-WSL.ps1 -UseSparse
    .\Compact-WSL.ps1 -DistroName "Ubuntu-24.04" -SkipWindowsClean
#>

[CmdletBinding()]
param(
    [string]$DistroName = "Ubuntu-24.04",
    [switch]$UseSparse,
    [switch]$SkipWindowsClean
)

$ErrorActionPreference = "Stop"

# raw URL — iex 실행 시 관리자 권한 상승에 재사용
$SCRIPT_RAW_URL = 'https://raw.githubusercontent.com/dEitY719/dotfiles/main/windows/Compact-WSL.ps1'

# ── 0. 관리자 권한 자동 승격 ──────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[!] 관리자 권한이 필요합니다. 권한 상승 후 재실행합니다..." -ForegroundColor Yellow

    $extraArgs = @()
    if ($UseSparse)        { $extraArgs += "-UseSparse" }
    if ($SkipWindowsClean) { $extraArgs += "-SkipWindowsClean" }

    if ($PSCommandPath) {
        # 파일 실행 경로: 파일 경로 + 파라미터로 재실행
        $argList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-DistroName", "`"$DistroName`""
        ) + $extraArgs
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    } else {
        # iex 실행 경로: irm 으로 재다운로드 후 관리자 셸에서 실행
        $params = (@("-DistroName `"$DistroName`"") + $extraArgs) -join " "
        $cmd = "& ([scriptblock]::Create((irm '$SCRIPT_RAW_URL'))) $params"
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd
        ) -Verb RunAs
    }
    exit
}

function Get-VhdxSizeGB {
    param([string]$Path)
    if (Test-Path $Path) {
        return [math]::Round((Get-Item $Path).Length / 1GB, 2)
    }
    return $null
}

function Clear-Dir([string]$Path) {
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== WSL vhdx 압축 스크립트 ===" -ForegroundColor Cyan
Write-Host "대상 배포판: $DistroName`n"

# ── 1. vhdx 경로 자동 탐색 ────────────────────────────────────────────
Write-Host "[1/5] vhdx 경로 탐색 중..." -ForegroundColor Green

$lxssRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
$basePath = $null

foreach ($key in (Get-ChildItem $lxssRoot -ErrorAction SilentlyContinue)) {
    $props = Get-ItemProperty $key.PSPath
    if ($props.DistributionName -eq $DistroName) {
        $basePath = $props.BasePath
        break
    }
}

if (-not $basePath) {
    Write-Host "[X] '$DistroName' 배포판을 찾지 못했습니다." -ForegroundColor Red
    Write-Host "    아래 목록에서 정확한 이름을 확인하고 -DistroName 으로 다시 실행하세요:" -ForegroundColor Red
    wsl -l -v
    exit 1
}

# BasePath 의 \\?\ 접두사 제거
$basePath = $basePath -replace '^\\\\\?\\', ''

# vhdx 파일 탐색: ext4.vhdx 우선, 없으면 *.vhdx 단일 파일로 폴백
$vhdxPath = Join-Path $basePath "ext4.vhdx"
if (-not (Test-Path $vhdxPath)) {
    $found = @(Get-ChildItem $basePath -Filter "*.vhdx" -ErrorAction SilentlyContinue)
    if ($found.Count -eq 1) {
        $vhdxPath = $found[0].FullName
    } else {
        Write-Host "[X] vhdx 파일을 찾지 못했습니다." -ForegroundColor Red
        Write-Host "    BasePath (레지스트리 원본): $basePath" -ForegroundColor Red
        exit 1
    }
}

$sizeBefore = Get-VhdxSizeGB $vhdxPath
Write-Host "    경로: $vhdxPath"
Write-Host "    현재 크기: $sizeBefore GB`n"

# ── 2. shutdown 전 fstrim (회수량 극대화) ─────────────────────────────
Write-Host "[2/5] WSL 내부 fstrim 실행 중 (해제된 블록 trim)..." -ForegroundColor Green
try {
    wsl -d $DistroName -u root -- fstrim -av
} catch {
    Write-Host "    (fstrim 생략 — 무시하고 계속 진행)" -ForegroundColor DarkYellow
}

# ── 3. WSL 종료 ───────────────────────────────────────────────────────
Write-Host "`n[3/5] wsl --shutdown ..." -ForegroundColor Green
wsl --shutdown
Start-Sleep -Seconds 15   # vhdx 핸들이 완전히 풀릴 때까지 대기 (느린 시스템 대비)

# ── 4. 압축 또는 sparse 전환 ─────────────────────────────────────────
if ($UseSparse) {
    Write-Host "`n[4/5] sparse 모드로 전환 중..." -ForegroundColor Green
    wsl --manage $DistroName --set-sparse true
    Write-Host "    이후 자동으로 디스크가 줄어듭니다." -ForegroundColor Gray
}
else {
    Write-Host "`n[4/5] diskpart compact vdisk 실행 중..." -ForegroundColor Green
    $diskpartScript = @"
select vdisk file="$vhdxPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $diskpartScript -Encoding ASCII

    # diskpart 출력을 로그로 빼고(백그라운드), 진행 상황은 직접 그린다.
    # diskpart 의 '퍼센트 완료'는 \r 로 같은 줄을 덮어써서 그냥 흘리면 멈춘 듯 보이기 때문.
    $logOut = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process diskpart.exe -ArgumentList "/s `"$tmp`"" `
        -PassThru -NoNewWindow -RedirectStandardOutput $logOut

    # diskpart 가 로그를 쓰는 중에도 읽을 수 있도록 공유 모드로 연다
    function Get-SharedText([string]$path) {
        $fs = $null
        $sr = $null
        try {
            $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $sr = New-Object System.IO.StreamReader($fs)
            return $sr.ReadToEnd()
        } catch {
            return ''
        } finally {
            if ($null -ne $sr) { $sr.Close() }
            if ($null -ne $fs) { $fs.Close() }
        }
    }
    function Format-Bar([int]$pct, [int]$width = 28) {
        if ($pct -lt 0)   { $pct = 0 }
        if ($pct -gt 100) { $pct = 100 }
        $fill = [math]::Floor($width * $pct / 100)
        return ('#' * $fill) + ('.' * ($width - $fill))
    }

    $spin   = '|', '/', '-', '\'
    $pctRe  = [regex]::new('(\d+)\s*(?:%|퍼센트|percent)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
    $i = 0
    $cur = '?'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ""   # 진행 바를 그릴 빈 줄 확보

    while (-not $proc.HasExited) {
        $raw = Get-SharedText $logOut
        $m   = $pctRe.Matches($raw)
        $pct = if ($m.Count) { [int]$m[$m.Count - 1].Groups[1].Value } else { -1 }

        if ($i % 17 -eq 0) { $v = Get-VhdxSizeGB $vhdxPath; if ($null -ne $v) { $cur = $v } }
        $el = [int]$sw.Elapsed.TotalSeconds

        $lead = if ($pct -ge 0) { "  [{0}] {1,3}%" -f (Format-Bar $pct), $pct }
                else             { "  {0} 압축 준비 중..." -f $spin[$i % $spin.Count] }
        $line = "{0}  | 경과 {1}s | 현재 {2} GB" -f $lead, $el, $cur
        Write-Host ("`r" + $line.PadRight(70)) -NoNewline -ForegroundColor Cyan
        $i++
        Start-Sleep -Milliseconds 300
    }
    $sw.Stop()

    $done = "  [{0}] 100%  | 완료 ({1}s)" -f (Format-Bar 100), [int]$sw.Elapsed.TotalSeconds
    Write-Host ("`r" + $done.PadRight(70)) -ForegroundColor Cyan

    if ($proc.ExitCode -ne 0) {
        Write-Host "  [!] diskpart 종료 코드 $($proc.ExitCode) — 로그 확인:" -ForegroundColor Yellow
        Get-SharedText $logOut | Write-Host
    }
    Remove-Item $tmp, $logOut -ErrorAction SilentlyContinue

    $sizeAfter = Get-VhdxSizeGB $vhdxPath
    $saved = [math]::Round($sizeBefore - $sizeAfter, 2)
    Write-Host "`n    압축 전: $sizeBefore GB" -ForegroundColor Gray
    Write-Host "    압축 후: $sizeAfter GB"  -ForegroundColor Gray
    Write-Host "    회수량 : $saved GB"       -ForegroundColor Cyan
}

# ── 5. Windows 쪽 정리 (선택) ────────────────────────────────────────
if (-not $SkipWindowsClean) {
    Write-Host "`n[5/5] Windows 정리..." -ForegroundColor Green

    # 5-1. TEMP 정리
    Write-Host "    - TEMP 정리"
    Clear-Dir $env:TEMP

    # 5-2. Windows Update 캐시 (SoftwareDistribution\Download)
    Write-Host "    - Windows Update 캐시 정리"
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        $wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path $wuCache) { Clear-Dir $wuCache }
        Start-Service wuauserv -ErrorAction SilentlyContinue
    } catch {
        Write-Host "      (Update 캐시 정리 일부 실패 — 무시)" -ForegroundColor DarkYellow
    }

    # 5-3. Chrome 캐시 (Default 프로필만 정리; 다중 프로필 사용 시 나머지는 수동 삭제 필요)
    $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromeCache) {
        if (Get-Process chrome -ErrorAction SilentlyContinue) {
            Write-Host "    - Chrome 실행 중 -> 캐시 정리 건너뜀 (브라우저 닫고 재실행)" -ForegroundColor DarkYellow
        } else {
            Write-Host "    - Chrome 캐시 정리 (Default 프로필)"
            Clear-Dir $chromeCache
        }
    }

    # 5-4. cleanmgr GUI (시스템 파일 정리)
    Write-Host "    - 디스크 정리 도구 실행 (시스템 파일 정리 항목 직접 선택)"
    Start-Process cleanmgr.exe -ArgumentList "/lowdisk" -ErrorAction SilentlyContinue
}

Write-Host "`n=== 완료 ===" -ForegroundColor Cyan
Write-Host "WSL 재시작: 터미널에서 'wsl -d $DistroName' 실행`n"
