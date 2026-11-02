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
# The first hump (x 170..277) traced background bushes as cave background inside its rock
# shell: a hollow in its left side and a pocket at its foot. Both are enclosed, so filling
# them with rock changes the colours only; the surface the vehicle drives on stays the same.
for ($y = 150; $y -lt $mh; $y++) { for ($x = 170; $x -le 277; $x++) { if ($m[$y*$mw+$x] -eq [Classify]::CAVE) { $m[$y*$mw+$x] = [Classify]::ROCK } } }
# The contraption's shadow left a shallow pit under the spawn; the vehicle (y 178..201) starts on a flat floor.
for ($y = 202; $y -lt $mh; $y++) { for ($x = 58; $x -lt 96; $x++) { if ($m[$y*$mw+$x] -lt [Classify]::ROCK -or $m[$y*$mw+$x] -eq [Classify]::GRASS) { $m[$y*$mw+$x] = [Classify]::ROCK } } }

# The rock ledge in the middle cave (x 521..569, y 112..120) splits the passage from the
# middle sky bubble to the right-hand sky into an upper and a lower gap; it stays.
$ledgeX0 = 521; $ledgeY0 = 112; $ledgeX1 = 569; $ledgeY1 = 120
# Floating solid bits are background hills, crystal edges and bushes the tracer read as
# rock or grass; the vehicle would collide with them in open air.
$cleared = [Classify]::RemoveIslands($m, $mw, $mh, 1000, $ledgeX0, $ledgeY0, $ledgeX1, $ledgeY1)
"Floating scenery: $cleared pixels opened"

# The traced passages are narrower than the 24-pixel vehicle (its tilted corners reach
# 17 pixels from its centre). Open the cheapest corridors of radius 22, so a vehicle at any
# tilt has 5 pixels to spare: from above the spawn (vehicle centre 80,190) into the middle
# bubble, through both the upper and the lower gap around the ledge, and from the right-hand
# sky to above the finish ledge (flag 769,50; ledge top y=56). The ends sit clear of the
# floor, and no corridor may cut the middle or the finish ledge, which stay as traced.
$routeR = 22
# Keep masks: the middle ledge and the finish ledge under the flag (top y=56) always, plus a
# virtual wall at x=545 above the middle ledge (lower route) or below it (upper route), so
# each corridor really opens its own gap rather than detouring through the other one.
function New-Keep([int]$wallY0, [int]$wallY1) {
    $k = New-Object bool[] ($mw * $mh)
    for ($y = $ledgeY0; $y -le $ledgeY1; $y++) { for ($x = $ledgeX0; $x -le $ledgeX1; $x++) { if ($m[$y*$mw+$x] -ge [Classify]::ROCK) { $k[$y*$mw+$x] = $true } } }
    for ($y = 56; $y -lt $mh; $y++) { for ($x = 735; $x -lt $mw; $x++) { if ($m[$y*$mw+$x] -ge [Classify]::ROCK) { $k[$y*$mw+$x] = $true } } }
    for ($y = $wallY0; $y -le $wallY1; $y++) { $k[$y*$mw+545] = $true }
    return ,$k
}
$keepAny = New-Keep 0 -1
$keepUpper = New-Keep ($ledgeY1 + 1) ($mh - 1)
$keepLower = New-Keep 0 ($ledgeY0 - 1)
$overY = $ledgeY0 - $routeR - 2; $underY = $ledgeY1 + $routeR + 2
$legs = @(
    @(80, 170, 455, 130, $keepAny),                                             # Start to the middle bubble (first gap)
    @(455, 130, 545, $overY, $keepUpper), @(545, $overY, 625, 110, $keepUpper), # Over the ledge
    @(455, 130, 545, $underY, $keepLower), @(545, $underY, 625, 110, $keepLower), # Under the ledge
    @(625, 110, 777, 33, $keepAny))                                             # Up to just above the finish ledge
$opened = 0
foreach ($leg in $legs) { $opened += [Classify]::CarveRoute($m, $mw, $mh, $leg[0], $leg[1], $leg[2], $leg[3], $routeR, 3.0, $leg[4]) }
"Flight corridors: $opened pixels opened"

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("// Cave Flight map: 1024 entries per row (x $mw..1023 unused), $mh rows. Classes: 0 sky, 1 cave, 2 rock, 3 grass, 4 road, 5 underground.")
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 1024; $x++) { [void]$sb.AppendLine($(if ($x -lt $mw) { $m[$y*$mw+$x] } else { 0 })) } }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_flight_map.mem'), $sb.ToString())
[MapTool]::Save((Join-Path $root 'docs\maps\cave_flight_classes.png'), [MapTool]::Crop([Classify]::Colour($m), $mw, 0, 0, $mw, $mh, 2), $mw*2, $mh*2)
# Board-accurate preview (one map pixel per world pixel, no moon), shown at 2x like the classes image.
[MapTool]::Save((Join-Path $root 'docs\maps\cave_flight_render.png'), [MapTool]::Crop([Classify]::Render($m, $mw, $mh, 1, -1, -1, 769, 50), $mw, 0, 0, $mw, $mh, 2), $mw*2, $mh*2)
"Map ${mw} x $mh written"

# Write the synthesis-safe one-bit collision ROM alongside the colour map.
$solid = New-Object System.Text.StringBuilder
[void]$solid.AppendLine('// Explicit collision ROM: 0=open sky/cave background; 1=solid terrain.')
for ($y = 0; $y -lt $mh; $y++) { for ($x = 0; $x -lt 1024; $x++) {
    $isSolid = $x -lt $mw -and $m[$y*$mw+$x] -ge [Classify]::ROCK -and $m[$y*$mw+$x] -le [Classify]::DARK
    [void]$solid.AppendLine($(if ($isSolid) { '1' } else { '0' }))
} }
[IO.File]::WriteAllText((Join-Path $root 'GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_flight_solid.mem'), $solid.ToString())

# Keep each colour ROM within one 32768-word Artix-7 BRAM depth. Explicit
# banks avoid synthesis-dependent hard-cascade address wiring in the large ROM.
for ($bank = 0; $bank -lt 7; $bank++) {
    $bankWords = New-Object System.Text.StringBuilder
    [void]$bankWords.AppendLine("// Cave Flight colour bank $bank, 32768 words, unused rows padded with sky.")
    for ($offset = 0; $offset -lt 32768; $offset++) {
        $bankY = $bank * 32 + ($offset -shr 10)
        $bankX = $offset -band 1023
        $bankClass = if ($bankY -lt $mh -and $bankX -lt $mw) { $m[$bankY*$mw+$bankX] } else { 0 }
        [void]$bankWords.AppendLine($bankClass)
    }
    [IO.File]::WriteAllText((Join-Path $root "GPT_6_S2_01_I-FDP_project.srcs\sources_1\new\cave_flight_colour_$bank.mem"), $bankWords.ToString())
}
