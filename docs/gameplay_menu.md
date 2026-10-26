# Gameplay menu and directional construction

Owner: Role 1 - Kaushal. Rendering uses Marcus's existing sprites.

## Construction

The grid stays at x4..51, y4..51 with 16-pixel cells. Three numbered boxes at x20..33, x34..47 and x48..61, y55..63 select inventory pages directly. Page 1 keeps frame, pig, wheel, engine and balloon. Page 2 contains the rocket and page 3 the fan. Both start with one item; `ROCKET_LIMIT` and `FAN_LIMIT` are adjustable top/builder parameters.

Pig and engine occupy a frame. Wheels require a frame directly above or below, balloons directly below, and rockets/fans directly to the left or right. Horizontal support never wraps across rows. A rocket or fan occupies its own unframed cell. Fan and rocket each add two provisional mass units while intact; Kyle should confirm these values with his thrust implementation.

Left-click and release an existing engine or rocket in the same cell to flip it. Dragging to another cell preserves its direction. Flipping works at zero remaining stock and consumes no parts. Inventory icons keep one orientation, with a small direction arrow before the count; balloons always show an up arrow. The drag preview, editor and map use the saved facing by transforming the same sprite data. `build_facing_left[8:0]` stores one bit per cell: 0 right, 1 left. Removing/returning clears it, and damage never changes it.

Dragging a filled frame picks up its contents first and leaves the frame visible and stationary. Returning those contents refunds only the contents. Dragging an empty frame moves that frame. Occupied/unsupported/outside drops, right-click cancellation and same-cell drops leave the source unchanged. The builder also rejects a direct attempt to move a filled frame as a bundle.

The bottom toolbar contains GO, three numbered inventory boxes, a book with a question mark and a settings gear. Placement/removal/error messages temporarily replace the toolbar for the existing one-second feedback duration, with the matching cell outline. The toolbar returns when feedback expires. The diary has three information pages with direct 1/2/3 navigation. Settings contains Audio and Map Selection; audio Back and map Back return to Settings, while choosing a map returns to BUILD. Audio volume and construction survive menu navigation. U closes these menus as a physical fallback.

## During RUN

The left OLED starts on DRIVE. Its bottom tabs are engine (x0..31), balloon (x32..63) and speaker (x64..95) icons, all at y55..63. The selected tab has a yellow mark. Navigation and controls require fresh left clicks; held/right clicks and the hidden JA builder view cannot replay actions.

* DRIVE: engine ON/OFF (x4..91, y12..21), fan (y23..32), boost (y34..43), rocket (y45..53). It contains no inventory or surviving-part count; normal engine control is on-screen.
* POP: a compact 36 by 36 vehicle diagram at x4..39, y12..47; click the balloon itself to pop it. The other menu pages do not send balloon requests. Grid cells and runtime damage stay unchanged by page navigation.
* SOUND: volume -/+, current volume and an on-screen MUTE button. RUN keeps moving while the menu is used; this is not a pause menu.

The top-right RETRY button (x66..95, y0..9) retries the current level. It restores the saved construction/direction and runtime parts, resets time and controls, returns to DRIVE, and preserves volume. EDIT returns to BUILD on the same level and restores the construction. Its hitbox is x40..65, y0..9 on DRIVE/SOUND; on POP it is x56..83, y14..23 so it does not cover a balloon. Retry/edit can cancel a movement transaction through the existing INIT_RUN/BUILD reset paths.

Physical controls remain as lab/debug fallbacks: C launches/retries, U opens/closes the diary in BUILD or edits during RUN, D fully resets, L jumps, SW1 mutes, SW2 reverses, SW3 sets normal zoom, SW4 enables free look, SW15 selects JA map view. Result-screen NEXT after success still advances a level. BTNR remains reserved and silent.

The timer on the Basys3 displays M.SS and runs through 4:15. Mouse-wheel steps select close (12-pixel), normal (8-pixel), overview (6-pixel), and wide overview (4-pixel) scales. Positive wheel deltas zoom out; negative deltas zoom in. Wide overview covers 192 by 128 world pixels and samples the existing sprites; it adds no sprite ROM. The existing two zoom bits encode all four scales: {overview,zoomed_out} = 00, 01, 11, 10. SW3 still selects close/normal. Zoom changes are latched at frame boundaries.

## Physics integration

Engine direction already feeds the existing physics inputs without modifying Kyle's arithmetic. `engine_balance` is the number of surviving right-facing engines minus surviving left-facing engines. The top supplies its absolute value as the effective engine count and XORs its sign with SW2 for reverse. Thus opposing engines cancel thrust, SW2 reverses the entire engine balance, and damage immediately updates the next movement sample. Existing ground-only thrust, boost, friction and jump rules remain.

Fan/rocket construction, sprites, stock and rocket direction storage are present. Their DRIVE controls display WAIT and stay disabled in the connected top until Kyle connects physics availability/readiness. `ui_controller.fan_available`, `rocket_available` and `rocket_ready` gate `fan_on` and the one-clock `rocket_req`; `ui_fan_on` and `ui_rocket_req` are named top wires for that integration. Do not enable these gates until physics consumes the outputs. The global frame snapshot is 239 + 4*(LP_COORD_BITS-16) bits, including two bits for the inventory page.

## Validation

`gameplay_menu_tb` drives the real mouse path and hardware top through directional placement, contents-only and empty-frame moves, side attachment rejection, stock, SW2, menu navigation, popping, volume, retry/edit and physical shortcuts. Existing move, balloon, audio and UI benches are updated for the new behaviour. `ui_visual_tb` exports real build, directional build, second inventory page, DRIVE, POP and SOUND pixels for review. Full-board timing, a fresh bitstream and physical OLED/mouse checks are still required before demonstration.

The 26 October UI revision passes 11 targeted benches: gameplay menu, directional parts, zoom controls, level selector, construction feedback, UI controls, volume audio, air controls, visual output, grid moves and single-OLED switching. Visual checks include the balloon up arrow, visible error text over the toolbar and the wide camera's world-coordinate coverage. The older `vehicle_builder_tb` still fails its surviving-pig pixel assertion; the same assertion fails against the saved pre-change sources, which already use the compact RUN grid. No claim is made that the full historical suite passes.

Same-device synthesis comparison (xc7a35tcpg236-1, Vivado 2025.2):

| Resource | Before these UI edits | Final UI, including wide zoom |
| --- | ---: | ---: |
| LUTs | 16,526 (79.45%) | 16,421 (78.95%) |
| Flip-flops | 2,924 | 2,940 |
| Block RAM tiles | 36.5 | 36.5 |
| DSPs | 33 | 33 |

The net change is **105 fewer LUTs**, with 16 extra flip-flops and no extra RAM or DSPs. Sharing the sprite lookups for both overview scales avoids a separate wide-view drawing path. An intermediate version with duplicated lookups used 17,039 LUTs; that version was replaced. These are synthesis results, not routed utilization or timing. The exact final report is `tmp/ui_verified/utilization.rpt`; the saved pre-change report is `tmp/ui_before/utilization.rpt`. No new bitstream was generated for this revision.
