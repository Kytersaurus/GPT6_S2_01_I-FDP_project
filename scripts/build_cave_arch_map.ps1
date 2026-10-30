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
# Trace correction: smoothing joined a rock horn to the upper end of the grass ramp
# under the arch (map x=205..222, y=153..167), closing the passage into the lower cave
# to 10 pixels; the screenshots show it open. Rock left of the ramp's grass edge in
# those rows becomes sky, giving the 24-pixel vehicle (12 map pixels at 2x) room.
for ($y = 153; $y -le 167; $y++) {
    $edge = -1
    for ($x = 205; $x -lt 240; $x++) { if ($m[$y*$mw+$x] -eq [Classify]::GRASS) { $edge = $x; break } }
    for ($x = 205; $x -lt $edge; $x++) { if ($m[$y*$mw+$x] -eq [Classify]::ROCK) { $m[$y*$mw+$x] = [Classify]::SKY } }
}

# Decorative grass (bushes, tufts, floating or hanging blobs) is drawn but must not block
# the cart. The same rule applies to every pixel; no area of the map is special-cased.
#  1. A grass patch (8-connected) that touches no rock, road or underground is floating
#     scenery and is open.
#  2. In a patch that touches ground, a vertical grass run of up to 5 pixels is the ground
#     skin (or a thin bridge) and stays solid.
#  3. A taller run sitting on ground keeps its bottom 2 pixels, so a bush leaves the same
#     skin as the grass around it; a taller run over open space (hanging) keeps nothing.
#  4. Grass with ground within 2 pixels to the left or right is wall grass and stays solid.
$decor = New-Object 'bool[]' ($mw*$mh)
function Test-Ground($v) { $v -eq [Classify]::ROCK -or $v -eq [Classify]::ROAD -or $v -eq [Classify]::DARK }
$patch = New-Object 'int[]' ($mw*$mh)
$grounded = New-Object System.Collections.Generic.List[bool]
[void]$grounded.Add($false)
$queue = New-Object System.Collections.Generic.Queue[int]
for ($i = 0; $i -lt $mw*$mh; $i++) {
    if ($m[$i] -ne [Classify]::GRASS -or $patch[$i] -ne 0) { continue }
    $id = $grounded.Count; $touches = $false
    $patch[$i] = $id; $queue.Enqueue($i)
    while ($queue.Count -gt 0) {
        $p = $queue.Dequeue(); $px = $p % $mw; $py = [math]::Floor($p / $mw)
        for ($dy = -1; $dy -le 1; $dy++) { for ($dx = -1; $dx -le 1; $dx++) {
            $nx = $px+$dx; $ny = $py+$dy
            if ($nx -lt 0 -or $nx -ge $mw -or $ny -lt 0 -or $ny -ge $mh) { continue }
            $n = $ny*$mw+$nx
            if (Test-Ground $m[$n]) { $touches = $true }
            elseif ($m[$n] -eq [Classify]::GRASS -and $patch[$n] -eq 0) { $patch[$n] = $id; $queue.Enqueue($n) }
        } }
    }
    [void]$grounded.Add($touches)
}
for ($x = 0; $x -lt $mw; $x++) {
    $y = 0
    while ($y -lt $mh) {
        if ($m[$y*$mw+$x] -ne [Classify]::GRASS) { $y++; continue }
        $start = $y
        while ($y -lt $mh -and $m[$y*$mw+$x] -eq [Classify]::GRASS) { $y++ }
        if (-not $grounded[$patch[$start*$mw+$x]]) {
            for ($g = $start; $g -lt $y; $g++) { $decor[$g*$mw+$x] = $true }
            continue
        }
        if ($y - $start -le 5) { continue }
        $keep = if ($y -lt $mh -and -not (Test-Ground $m[$y*$mw+$x])) { 0 } else { 2 }
        for ($g = $start; $g -lt $y - $keep; $g++) {
            $beside = $false
            foreach ($d in -2, -1, 1, 2) {
                if ($x+$d -ge 0 -and $x+$d -lt $mw -and (Test-Ground $m[$g*$mw+$x+$d])) { $beside = $true }
            }
            if (-not $beside) { $decor[$g*$mw+$x] = $true }
        }
    }
}

# Smooth the traced terrain (Classify.SmoothTerrain): floor lumps and dips up to 4 pixels
# wide are levelled, notches filled and spikes removed, everywhere on the map. Pixels
# whose solidity changes are recoloured, so the drawn map matches what the cart drives on.
$terrain = [Classify]::SmoothTerrain($m, $decor, $mw, $mh)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// Cave Arch map: 512 entries per row (x $mw..511 unused), $mh rows. Classes: 0 sky, 1 cave, 2 rock, 3 grass, 4 road, 5 underground.")
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 512; $x++) { [void]$sb.AppendLine($(if ($x -lt $mw) { $m[$y*$mw+$x] } else { 0 })) } }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_arch_map.mem'), $sb.ToString())
[MapTool]::Save((Join-Path $root 'docs\maps\cave_arch_classes.png'), [MapTool]::Crop([Classify]::Colour($m), $mw, 0, 0, $mw, $mh, 2), $mw*2, $mh*2)
"Map ${mw} x $mh written"

# Write the synthesis-safe one-bit collision ROM alongside the colour map.
$solid = New-Object System.Text.StringBuilder
[void]$solid.AppendLine('// Explicit collision ROM: 0=open sky/cave background or decorative grass; 1=solid terrain.')
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 512; $x++) {
    $isSolid = $x -lt $mw -and $terrain[$y*$mw+$x]
    [void]$solid.AppendLine($(if ($isSolid) { '1' } else { '0' }))
} }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_arch_solid.mem'), $solid.ToString())
