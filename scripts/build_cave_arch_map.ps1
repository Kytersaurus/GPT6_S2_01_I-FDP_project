# Owner: Role 4 - Marcus. Rebuilds the Cave Arch map ROM from the reference screenshots.
# Usage (from the repository root): powershell -ExecutionPolicy Bypass -File scripts/build_cave_arch_map.ps1
# Reads docs/maps/cave_arch_reference_top.png and _bottom.png, classifies every pixel
# (sky, cave background, rock, grass, road, underground), halves the resolution to
# world pixels and writes cave_arch_map.mem beside the HDL plus docs/maps/cave_arch_classes.png.
# Keep LP_MAP_WIDTH/LP_MAP_HEIGHT in game_defs.vh equal to the printed size.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $PSScriptRoot 'map_tools'
Add-Type -AssemblyName PresentationCore, WindowsBase
Add-Type -Path (Join-Path $tools 'maptool.cs'), (Join-Path $tools 'classify.cs') -ReferencedAssemblies PresentationCore, WindowsBase, System.Xaml

$w1 = 0; $h1 = 0; $top = [MapTool]::Load((Join-Path $root 'docs\maps\cave_arch_reference_top.png'), [ref]$w1, [ref]$h1)
$w2 = 0; $h2 = 0; $bottom = [MapTool]::Load((Join-Path $root 'docs\maps\cave_arch_reference_bottom.png'), [ref]$w2, [ref]$h2)
# The bottom screenshot overlaps the top one, 1 pixel right and 143 pixels down (measured by image matching).
$w = 0; $h = 0
$c = [Classify]::Merge($top, $w1, $h1, $bottom, $w2, $h2, 1, 143, [ref]$w, [ref]$h)
[Classify]::Fill($c, $w, 205, 55, 250, 100, [Classify]::SKY)       # Contraption at the start
$c = [Classify]::Smooth($c, $w, $h, 2); $c = [Classify]::Smooth($c, $w, $h, 2)
[Classify]::RemoveSmall($c, $w, $h, [Classify]::DARK, 3000); [Classify]::RemoveSmall($c, $w, $h, [Classify]::ROAD, 3000)
[Classify]::RemoveSmall($c, $w, $h, [Classify]::SKY, 1800)          # Crystals
[Classify]::RemoveSmall($c, $w, $h, [Classify]::CAVE, 400); [Classify]::RemoveSmall($c, $w, $h, [Classify]::ROCK, 400)
[Classify]::Fill($c, $w, 948, 0, $w, $h, [Classify]::SKY)          # Black right border of the screenshots
[Classify]::Fill($c, $w, 0, 560, $w, $h, [Classify]::DARK)         # Below the silhouettes
$mw = 0; $mh = 0
$m = [Classify]::Down($c, $w, $h, 2, [ref]$mw, [ref]$mh)

# Remove the decorative bush hanging inside the first valley below the arch.
# This isolated grass patch is scenery, not the grass road at y=117..124.
# Restrict the cleanup to its photographed bounds and GRASS pixels so nearby
# cave rock and the real supporting surface remain unchanged.
for ($y = 92; $y -le 100; $y++) {
    for ($x = 225; $x -le 231; $x++) {
        if ($m[$y*$mw+$x] -eq [Classify]::GRASS) { $m[$y*$mw+$x] = [Classify]::CAVE }
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// Cave Arch map: 512 entries per row (x $mw..511 unused), $mh rows. Classes: 0 sky, 1 cave, 2 rock, 3 grass, 4 road, 5 underground.")
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 512; $x++) { [void]$sb.AppendLine($(if ($x -lt $mw) { $m[$y*$mw+$x] } else { 0 })) } }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_arch_map.mem'), $sb.ToString())
[MapTool]::Save((Join-Path $root 'docs\maps\cave_arch_classes.png'), [MapTool]::Crop([Classify]::Colour($m), $mw, 0, 0, $mw, $mh, 2), $mw*2, $mh*2)
"Map ${mw} x $mh written"

# Write the synthesis-safe one-bit collision ROM alongside the colour map.
$solid = New-Object System.Text.StringBuilder
[void]$solid.AppendLine('// Explicit collision ROM: 0=open sky/cave background; 1=solid terrain.')
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 512; $x++) {
    $isSolid = $x -lt $mw -and $m[$y*$mw+$x] -ge [Classify]::ROCK -and $m[$y*$mw+$x] -le [Classify]::DARK
    [void]$solid.AppendLine($(if ($isSolid) { '1' } else { '0' }))
} }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_arch_solid.mem'), $solid.ToString())
