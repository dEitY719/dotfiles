# mytool/install-meslo-font.ps1
# Install Meslo LG Nerd Font for Windows Terminal
# Run this script with admin privileges

param(
    [switch]$SkipPause = $false
)

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires administrator privileges!" -ForegroundColor Red
    Write-Host "Please run this script as Administrator." -ForegroundColor Yellow
    if (-not $SkipPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
    }
    exit 1
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          Meslo LG Nerd Font Installer for Windows             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

try {
    # Download font
    $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip"
    $output = "$env:TEMP\Meslo.zip"

    Write-Host "📥 Downloading Meslo LG NF..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $output -ErrorAction Stop
    Write-Host "✅ Download complete" -ForegroundColor Green

    # Create temporary extraction folder
    $tempExtract = "$env:TEMP\MesloExtract"
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    $null = mkdir $tempExtract -Force

    Write-Host "📦 Extracting fonts..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($output, $tempExtract)
    Write-Host "✅ Extraction complete" -ForegroundColor Green

    # Install fonts to Windows Fonts directory
    $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    $fontCount = 0

    Write-Host "💾 Installing fonts to Windows..." -ForegroundColor Cyan
    Get-ChildItem $tempExtract -Include @("*.ttf", "*.otf") -Recurse | ForEach-Object {
        Copy-Item $_.FullName $fontDir -Force -ErrorAction SilentlyContinue
        Write-Host "   ✓ $($_.Name)" -ForegroundColor Green
        $fontCount++
    }

    # Cleanup
    Write-Host "🧹 Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $output -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Cleanup complete" -ForegroundColor Green

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    Installation Complete! ✅                    ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Summary:" -ForegroundColor Cyan
    Write-Host "   • Fonts installed: $fontCount" -ForegroundColor White
    Write-Host "   • Location: $fontDir" -ForegroundColor White
    Write-Host ""
    Write-Host "📝 Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Close Windows Terminal completely (all tabs)" -ForegroundColor White
    Write-Host "   2. Open Windows Terminal again" -ForegroundColor White
    Write-Host "   3. Go to Settings → Profiles → Defaults → Appearance" -ForegroundColor White
    Write-Host "   4. Select Font face: 'Meslo LG NF' (or search 'Meslo')" -ForegroundColor White
    Write-Host "   5. Font size: 10-12pt recommended" -ForegroundColor White
    Write-Host "   6. Click Save" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host "❌ ERROR: $_" -ForegroundColor Red
    if (-not $SkipPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
    }
    exit 1
}

if (-not $SkipPause) {
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    [void][System.Console]::ReadKey($true)
}
