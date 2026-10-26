# Gameplay menu and directional construction

Owner: Role 1 - Kaushal. Rendering uses Marcus's existing sprites.

## Construction

The grid stays at x4..51, y4..51 with 16-pixel cells. Inventory page P1 keeps the original five rows: frame, pig, wheel, engine and balloon. The P1/P2 button at x20..39, y55..63 switches to page P2, where the first two rows contain rocket and fan. Both start with one item; `ROCKET_LIMIT` and `FAN_LIMIT` are adjustable top/builder parameters.

Pig and engine occupy a frame. Wheels require a frame directly above or below, balloons directly below, and rockets/fans directly to the left or right. Horizontal support never wraps across rows. A rocket or fan occupies its own unframed cell. Fan and rocket each add two provisional mass units while intact; Kyle should confirm these values with his thrust implementation.

After selecting an engine or rocket, choose < (x42..51) or > (x53..62) in the bottom toolbar before placement. Yellow marks the selected direction. The inventory icon, drag preview, editor sprite and map sprite all use it. Rockets are rotated from the original upward-facing sprite to face horizontally. `build_facing_left[8:0]` stores one bit per cell: 0 right, 1 left, in vehicle coordinates. Moving the part preserves that bit, replacing/removing/returning clears or updates it, and damage never changes the saved direction.

Dragging a filled frame picks up its contents first and leaves the frame visible and stationary. Returning those contents refunds only the contents. Dragging an empty frame moves that frame. Occupied/unsupported/outside drops, right-click cancellation and same-cell drops leave the source unchanged. The builder also rejects a direct attempt to move a filled frame as a bundle.

The compact bottom toolbar now contains GO, P1/P2, direction arrows, diary ? and a readable MAP button. Construction feedback highlights the affected grid cell; the old bottom status text and decorative blue strip are removed. The diary explains attachment rules and the POP page.

## During RUN

The left OLED starts on DRIVE. Its bottom tabs are engine (x0..31), balloon (x32..63) and speaker (x64..95) icons, all at y55..63. The selected tab has a yellow mark. Navigation and controls require fresh left clicks; held/right clicks and the hidden JA builder view cannot replay actions.

* DRIVE: engine ON/OFF (x4..91, y12..21), fan (y23..32), boost (y34..43), rocket (y45..53). It contains no inventory or surviving-part count; normal engine control is on-screen.
* POP: a compact 36 by 36 vehicle diagram at x4..39, y12..47; click the balloon itself to pop it. The other menu pages do not send balloon requests. Grid cells and runtime damage stay unchanged by page navigation.
* SOUND: volume -/+, current volume and an on-screen MUTE button. RUN keeps moving while the menu is used; this is not a pause menu.

The top-right RETRY button (x66..95, y0..9) retries the current level. It restores the saved construction/direction and runtime parts, resets time and controls, returns to DRIVE, and preserves volume. EDIT returns to BUILD on the same level and restores the construction. Its hitbox is x40..65, y0..9 on DRIVE/SOUND; on POP it is x56..83, y14..23 so it does not cover a balloon. Retry/edit can cancel a movement transaction through the existing INIT_RUN/BUILD reset paths.

Physical controls remain as lab/debug fallbacks: C launches/retries, U opens/closes the diary in BUILD or edits during RUN, D fully resets, L jumps, SW1 mutes, SW2 reverses, SW3 sets normal zoom, SW4 enables free look, SW15 selects JA map view. Result-screen NEXT after success still advances a level. BTNR remains reserved and silent.

The timer on the Basys3 now displays M.SS and runs through 4:15. Mouse-wheel steps select close (12-pixel), normal (8-pixel), and overview (6-pixel) map scales; overview gives free-look a wider map view.

## Physics integration

Engine direction already feeds the existing physics inputs without modifying Kyle's arithmetic. `engine_balance` is the number of surviving right-facing engines minus surviving left-facing engines. The top supplies its absolute value as the effective engine count and XORs its sign with SW2 for reverse. Thus opposing engines cancel thrust, SW2 reverses the entire engine balance, and damage immediately updates the next movement sample. Existing ground-only thrust, boost, friction and jump rules remain.

Fan/rocket construction, sprites, stock and direction storage are present. Their DRIVE controls display WAIT and stay disabled in the connected top until Kyle connects physics availability/readiness. `ui_controller.fan_available`, `rocket_available` and `rocket_ready` gate `fan_on` and the one-clock `rocket_req`; `ui_fan_on` and `ui_rocket_req` are named top wires for that integration. Do not enable these gates until physics consumes the outputs. The global frame snapshot is 238 bits and includes the new page, orientation, inventory and mute display data.

## Validation

`gameplay_menu_tb` drives the real mouse path and hardware top through directional placement, contents-only and empty-frame moves, side attachment rejection, stock, SW2, menu navigation, popping, volume, retry/edit and physical shortcuts. Existing move, balloon, audio and UI benches are updated for the new behaviour. `ui_visual_tb` exports real build, directional build, second inventory page, DRIVE, POP and SOUND pixels for review. Full-board timing, a fresh bitstream and physical OLED/mouse checks are still required before demonstration.
