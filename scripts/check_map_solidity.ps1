# Verify every map pixel through synthesized block RAM, not just RTL arrays.
param([string]$VivadoBin = 'C:\AMDDesignTools\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$lpRoot = Split-Path -Parent $PSScriptRoot
$lpSrc = Join-Path $lpRoot 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new'
$lpWork = Join-Path $lpRoot 'tmp\map_solidity_synthesis'
New-Item -ItemType Directory -Force -Path $lpWork | Out-Null
& (Join-Path $VivadoBin 'vivado.bat') -mode batch -source ((Join-Path $PSScriptRoot 'check_map_solidity.tcl').Replace('\','/')) -log (Join-Path $lpWork 'synthesis.log') -journal (Join-Path $lpWork 'synthesis.jou') -tclargs ((Split-Path -Parent $VivadoBin).Replace('\','/')) ($lpRoot.Replace('\','/'))
if ($LASTEXITCODE -ne 0) { throw 'Collision ROM synthesis failed.' }
if (Select-String -LiteralPath (Join-Path $lpWork 'synthesis.log') -Pattern 'ignoring malformed.*readmem' -Quiet) {
    throw 'Synthesis ignored a collision ROM initialization.'
}
Get-ChildItem -LiteralPath $lpSrc -Filter '*.mem' | Copy-Item -Destination $lpWork -Force
Push-Location $lpWork
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv -d POST_SYNTHESIS -i $lpSrc (Join-Path $lpWork 'map_mask_netlist.v') (Join-Path $lpRoot 'sim\map_solidity_tb.v')
    if ($LASTEXITCODE -ne 0) { throw 'Post-synthesis ROM compilation failed.' }
    & (Join-Path $VivadoBin 'xelab.bat') -L unisims_ver work.map_solidity_tb work.glbl -s map_solidity_hardware
    if ($LASTEXITCODE -ne 0) { throw 'Post-synthesis ROM elaboration failed.' }
    & (Join-Path $VivadoBin 'xsim.bat') map_solidity_hardware -runall -onfinish quit -log hardware_check.log
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath hardware_check.log -SimpleMatch 'PASS map_solidity_tb:' -Quiet)) {
        throw 'Post-synthesis map solidity verification failed.'
    }
} finally { Pop-Location }
