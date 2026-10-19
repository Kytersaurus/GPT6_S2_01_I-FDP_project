# Owner: Shared - all roles maintain the runner and their own simulation checks.
param(
    [string]$VivadoBin = 'C:\AMDDesignTools\2025.2\Vivado\bin',
    [string[]]$Benches = @('game_baseline_tb', 'module_contracts_tb', 'display_snapshot_tb', 'physics_engine_tb', 'clock_control_tb', 'button_debouncer_tb', 'vehicle_builder_tb', 'construction_controls_tb')
)
$ErrorActionPreference = 'Stop'
$lpRepoRoot = Split-Path -Parent $PSScriptRoot
$lpSourceDir = Join-Path $lpRepoRoot 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new'
$lpWorkDir = Join-Path $lpRepoRoot 'tmp\baseline_sim'
New-Item -ItemType Directory -Force -Path $lpWorkDir | Out-Null
Push-Location $lpWorkDir
try {
    $lpVhdl = @(Get-ChildItem -LiteralPath $lpSourceDir -Filter '*.vhd' | ForEach-Object { $_.FullName })
    & (Join-Path $VivadoBin 'xvhdl.bat') @lpVhdl
    if ($LASTEXITCODE -ne 0) { throw 'Mouse driver compilation failed.' }
    $lpSources = @(Get-ChildItem -LiteralPath $lpSourceDir -Filter '*.v' | ForEach-Object { $_.FullName })
    $lpSources += @(Get-ChildItem -LiteralPath (Join-Path $lpRepoRoot 'sim') -Filter '*_tb.v' | ForEach-Object { $_.FullName })
    & (Join-Path $VivadoBin 'xvlog.bat') --sv -i $lpSourceDir @lpSources
    if ($LASTEXITCODE -ne 0) { throw 'HDL compilation failed.' }
    foreach ($lpBench in $Benches) {
        & (Join-Path $VivadoBin 'xelab.bat') ('work.' + $lpBench) -s $lpBench
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed for $lpBench" }
        $lpLog = Join-Path $lpWorkDir ($lpBench + '.log')
        & (Join-Path $VivadoBin 'xsim.bat') $lpBench -runall -onfinish quit -log $lpLog
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed for $lpBench" }
        if (-not (Select-String -LiteralPath $lpLog -SimpleMatch ('PASS ' + $lpBench) -Quiet)) {
            throw "Simulation did not report PASS for $lpBench. Inspect $lpLog"
        }
    }
} finally {
    Pop-Location
}
