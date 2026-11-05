param(
    [string]$VivadoBin = 'C:\AMDDesignTools\2025.2\Vivado\bin'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Write-Host "Starting Vivado synthesis and bitstream build..."
    & (Join-Path $VivadoBin 'vivado.bat') -mode batch -source scripts/build_bitstream.tcl
    if ($LASTEXITCODE -ne 0) { throw "Vivado build failed with exit code $LASTEXITCODE" }

    $bitFile = Join-Path $repoRoot 'tmp\bitstream_build\My_Top_Module.bit'
    if (Test-Path $bitFile) {
        $dateStr = Get-Date -Format 'yyyy-MM-dd'
        $timeStr = Get-Date -Format 'HHmmss'
        $builtIso = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
        $todayDir = Join-Path $repoRoot "bitstreams\$dateStr"
        New-Item -ItemType Directory -Force -Path $todayDir | Out-Null
        $relPath = "$dateStr/${timeStr}_My_Top_Module.bit"
        $archivedFile = Join-Path $todayDir "${timeStr}_My_Top_Module.bit"
        Copy-Item -LiteralPath $bitFile -Destination $archivedFile -Force
        Copy-Item -LiteralPath $bitFile -Destination (Join-Path $repoRoot 'bitstreams\bad_piggies_top_latest.bit') -Force

        $commitShort = (git rev-parse --short HEAD 2>$null)
        if (-not $commitShort) { $commitShort = 'working-tree' }
        $latestTxt = @(
            "Latest bitstream: $relPath"
            "Quick copy:       bitstreams/bad_piggies_top_latest.bit"
            "Built at:         $builtIso"
            "Source commit:    $commitShort"
            "Top module:       My_Top_Module (XC7A35T-1CPG236C)"
        )
        Set-Content -Path (Join-Path $repoRoot 'bitstreams\LATEST.txt') -Value $latestTxt -Encoding UTF8

        Write-Host "=========================================="
        Write-Host "SUCCESS: Bitstream generated and archived!"
        Write-Host "  -> bitstreams/$relPath"
        Write-Host "  -> bitstreams/bad_piggies_top_latest.bit"
        Write-Host "=========================================="
    } else {
        throw "Bitstream file not found at $bitFile"
    }
} finally {
    Pop-Location
}
