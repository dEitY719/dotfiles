Param(
    [string]$FontPattern = "*.ttf"
)

$fontSource = Split-Path -Parent $MyInvocation.MyCommand.Path
$fontTarget = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
$regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

Write-Host ""
Write-Host "Installing Nerd Fonts..."
Write-Host ("  Source : {0}" -f $fontSource)
Write-Host ("  Target : {0}" -f $fontTarget)
Write-Host ""

if (-not (Test-Path -LiteralPath $fontTarget)) {
    Write-Host "Creating font directory for current user..."
    New-Item -ItemType Directory -Path $fontTarget -Force | Out-Null
}

$fontFiles = Get-ChildItem -Path $fontSource -Filter $FontPattern -File | Sort-Object Name
if (-not $fontFiles) {
    Write-Warning "No *.ttf files found next to this script."
    exit 1
}

$installed = 0
$skipped = 0
$failed = 0
foreach ($font in $fontFiles) {
    $destination = Join-Path $fontTarget $font.Name
    if (Test-Path -LiteralPath $destination) {
        Write-Host ("Skipping {0} (already present)" -f $font.Name)
        $skipped++
        continue
    }
    try {
        Write-Host ("Installing {0} ..." -f $font.Name)
        Copy-Item -Path $font.FullName -Destination $destination -Force
        $regName = "{0} (TrueType)" -f $font.BaseName
        New-ItemProperty -Path $regPath -Name $regName -Value $font.Name -PropertyType String -Force | Out-Null
        $installed++
    } catch {
        $failed++
        Write-Warning ("Failed to install {0}: {1}" -f $font.Name, $_.Exception.Message)
    }
}

if ($installed -gt 0) {
    $sig = @"
using System;
using System.Runtime.InteropServices;
public static class FontRefresh {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@
    Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue | Out-Null
    [FontRefresh]::SendMessage([IntPtr]0xffff,0x001D,[IntPtr]0,[IntPtr]0) | Out-Null
    Write-Host ""
    Write-Host ("Installed {0} font(s). If Windows Terminal was open, restart it to pick up the new Meslo fonts." -f $installed)
}

if ($skipped -gt 0) {
    Write-Host ("Skipped {0} font(s) because they already exist." -f $skipped)
}

if ($failed -gt 0) {
    Write-Warning ("{0} font(s) failed to install. Close apps using these fonts (Windows Terminal, VS Code, etc.) and run again." -f $failed)
    exit 1
}

if ($installed -eq 0 -and $skipped -eq 0) {
    Write-Warning "No fonts were installed."
    exit 1
}

exit 0
