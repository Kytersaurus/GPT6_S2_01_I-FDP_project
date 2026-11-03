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
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
        $todayDir = Join-Path $repoRoot "bitstreams\$(Get-Date -Format 'yyyy-MM-dd')"
        New-Item -ItemType Directory -Force -Path $todayDir | Out-Null
        $archivedFile = Join-Path $todayDir "bad_piggies_top_${timestamp}.bit"
        Copy-Item -LiteralPath $bitFile -Destination $archivedFile -Force
        Copy-Item -LiteralPath $bitFile -Destination (Join-Path $repoRoot 'bitstreams\bad_piggies_top_latest.bit') -Force
        
        $rptUtil = Join-Path $repoRoot 'tmp\bitstream_build\utilization_routed.rpt'
        $rptTiming = Join-Path $repoRoot 'tmp\bitstream_build\timing_routed.rpt'
        Write-Host "=========================================="
        Write-Host "SUCCESS: Bitstream generated and archived!"
        Write-Host "  -> $archivedFile"
        Write-Host "  -> bitstreams/bad_piggies_top_latest.bit"
        Write-Host "=========================================="
    } else {
        throw "Bitstream file not found at $bitFile"
    }
} finally {
    Pop-Location
}

