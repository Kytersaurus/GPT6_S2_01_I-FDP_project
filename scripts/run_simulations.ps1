# Owner: Shared - all roles maintain the runner and their own simulation checks.
param(
    [string]$VivadoBin = 'C:\AMDDesignTools\2025.2\Vivado\bin',
    [string[]]$Benches = @('game_baseline_tb', 'module_contracts_tb', 'display_snapshot_tb', 'physics_engine_tb', 'clock_control_tb', 'button_debouncer_tb', 'vehicle_builder_tb', 'construction_controls_tb', 'balloon_controls_tb', 'sound_generator_tb', 'game_audio_tb', 'construction_feedback_tb', 'role4_game_display_tb', 'role4_level_solutions_tb', 'physics_friction_tb', 'physics_slope_tb', 'map_slope_tb', 'slope_map_integration_tb', 'rotation_map_integration_tb', 'rotating_collision_tb', 'occupied_map_collision_tb', 'rotation_interactions_tb', 'vehicle_rotation_renderer_tb', 'vehicle_rotation_top_tb', 'signed_divider16_tb', 'physics_jump_tb', 'team_controls_tb', 'collision_engine_tb', 'map_collision_tb', 'map_rom_collision_tb', 'map_solidity_tb', 'world_outcomes_tb', 'cave_coordinates_tb', 'cave_map_integration_tb', 'flip_physics_tb', 'cave_arch_drive_tb', 'tnt_controller_tb', 'tnt_integration_tb', 'bgm_player_tb', 'single_oled_tb', 'grid_moves_tb', 'boost_controls_tb', 'ui_controls_tb', 'timer_death_tb', 'ui_air_controls_tb', 'ui_visual_tb', 'level_selector_tb', 'volume_audio_tb', 'gameplay_menu_tb', 'directional_parts_tb', 'zoom_controls_tb', 'air_propulsion_tb', 'vehicle_moments_tb', 'physics_moments_tb', 'rocket_orientation_tb', 'rocket_game_integration_tb', 'wheel_stability_tb')
)
$ErrorActionPreference = 'Stop'
$lpRepoRoot = Split-Path -Parent $PSScriptRoot
$lpSourceDir = Join-Path $lpRepoRoot 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new'
$lpWorkDir = Join-Path $lpRepoRoot 'tmp\baseline_sim'
New-Item -ItemType Directory -Force -Path $lpWorkDir | Out-Null
Push-Location $lpWorkDir
try {
    # $readmemh files are opened relative to the simulator's working directory.
    Get-ChildItem -LiteralPath $lpSourceDir -Filter '*.mem' | Copy-Item -Destination $lpWorkDir -Force
    $lpVhdl = @(Get-ChildItem -LiteralPath $lpSourceDir -Filter '*.vhd' | ForEach-Object { $_.FullName })
    & (Join-Path $VivadoBin 'xvhdl.bat') @lpVhdl
    if ($LASTEXITCODE -ne 0) { throw 'Mouse driver compilation failed.' }
    $lpSources = @(Get-ChildItem -LiteralPath $lpSourceDir -Filter '*.v' | ForEach-Object { $_.FullName })
    $lpSources += @(Get-ChildItem -LiteralPath (Join-Path $lpRepoRoot 'sim') -Filter '*_tb.v' | ForEach-Object { $_.FullName })
    # cmd.exe expands the .bat invocation and has an 8191-character limit.
    # Keep batches bounded as the design and regression suite grow.
    for ($lpStart = 0; $lpStart -lt $lpSources.Count; $lpStart += 20) {
        $lpEnd = [Math]::Min($lpStart + 19, $lpSources.Count - 1)
        $lpBatch = $lpSources[$lpStart..$lpEnd]
        & (Join-Path $VivadoBin 'xvlog.bat') --sv -i $lpSourceDir @lpBatch
        if ($LASTEXITCODE -ne 0) { throw 'HDL compilation failed.' }
    }
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
