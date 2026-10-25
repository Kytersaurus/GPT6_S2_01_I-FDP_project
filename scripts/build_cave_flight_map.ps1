# Owner: Role 4 - Marcus. Rebuilds the Cave Flight map ROM from the reference screenshots.
# Usage (from the repository root): powershell -ExecutionPolicy Bypass -File scripts/build_cave_flight_map.ps1
# Reads docs/maps/cave_flight_reference_left.png and _right.png, classifies every pixel,
# halves the resolution to world pixels and writes cave_flight_map.mem beside the HDL plus
# docs/maps/cave_flight_classes.png. Keep LP_FLIGHT_WIDTH/LP_FLIGHT_HEIGHT in game_defs.vh
# equal to the printed size.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $PSScriptRoot 'map_tools'
Add-Type -AssemblyName PresentationCore, WindowsBase
Add-Type -Path (Join-Path $tools 'maptool.cs'), (Join-Path $tools 'classify.cs') -ReferencedAssemblies PresentationCore, WindowsBase, System.Xaml

# These screenshots are darker: blue well above green is sky or background scenery.
[Classify]::SkyBlueMargin = 22
$w1 = 0; $h1 = 0; $left = [MapTool]::Load((Join-Path $root 'docs\maps\cave_flight_reference_left.png'), [ref]$w1, [ref]$h1)
$w2 = 0; $h2 = 0; $right = [MapTool]::Load((Join-Path $root 'docs\maps\cave_flight_reference_right.png'), [ref]$w2, [ref]$h2)
# The right screenshot overlaps the left one at 832 pixels right and 12 pixels up (measured by image matching).
$w = 0; $h = 0
$c = [Classify]::Place($left, $w1, $h1, 0, 12, $right, $w2, $h2, 832, 0, $false, [ref]$w, [ref]$h)
[Classify]::FillUnknownNearest($c, $w, $h)                          # Under the UI and outside both shots
$c = [Classify]::Smooth($c, $w, $h, 2); $c = [Classify]::Smooth($c, $w, $h, 2)
[Classify]::RemoveSmall($c, $w, $h, [Classify]::DARK, 3000); [Classify]::RemoveSmall($c, $w, $h, [Classify]::ROAD, 3000)
[Classify]::RemoveSmall($c, $w, $h, [Classify]::SKY, 1800)          # Crystals
[Classify]::RemoveSmall($c, $w, $h, [Classify]::CAVE, 400); [Classify]::RemoveSmall($c, $w, $h, [Classify]::ROCK, 400)
$mw = 0; $mh = 0
$m = [Classify]::Down($c, $w, $h, 2, [ref]$mw, [ref]$mh)
[Classify]::CleanThin($m, $mw, $mh, [Classify]::SKY, 3)            # Seams along the UI edges
for ($y = 0; $y -lt 38; $y++) { for ($x = 590; $x -lt 640; $x++) { if ($m[$y*$mw+$x] -eq [Classify]::SKY) { $m[$y*$mw+$x] = [Classify]::ROCK } } }
for ($y = 170; $y -lt 202; $y++) { for ($x = 58; $x -lt 96; $x++) { $m[$y*$mw+$x] = [Classify]::SKY } }   # Contraption and bush at the start

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// Cave Flight map: 1024 entries per row (x $mw..1023 unused), $mh rows. Classes: 0 sky, 1 cave, 2 rock, 3 grass, 4 road, 5 underground.")
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 1024; $x++) { [void]$sb.AppendLine($(if ($x -lt $mw) { $m[$y*$mw+$x] } else { 0 })) } }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_flight_map.mem'), $sb.ToString())
[MapTool]::Save((Join-Path $root 'docs\maps\cave_flight_classes.png'), [MapTool]::Crop([Classify]::Colour($m), $mw, 0, 0, $mw, $mh, 2), $mw*2, $mh*2)
"Map ${mw} x $mh written"
