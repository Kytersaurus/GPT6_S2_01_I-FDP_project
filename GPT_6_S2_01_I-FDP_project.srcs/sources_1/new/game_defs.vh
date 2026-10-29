// Owner: Shared - all roles agree changes to these constants.
`ifndef LAGGY_PIGGIES_GAME_DEFS_VH
`define LAGGY_PIGGIES_GAME_DEFS_VH

// Shared definitions beside the game modules. Update docs/interfaces.md together.
`define LP_CLK_HZ        100000000
`define LP_GRID_COLS     3
`define LP_GRID_ROWS     3
`define LP_CELLS         9
`define LP_PART_BITS     3
`define LP_GRID_BITS     27
`define LP_CELL_BITS     4

// World positions are signed Q12.8; velocities retain signed 16-bit Q8.8.
`define LP_CELL_PIXELS   8
`define LP_COORD_BITS    20
`define LP_FRAC_BITS     8
// Vehicle tilt: signed 11.25 degree steps, -16..15 covers the full turn (-16 is upside down).
`define LP_TILT_BITS     5
`define LP_MAX_TERRAIN   4
`define LP_RECT_BITS     32

`define LP_PART_EMPTY    3'd0
`define LP_PART_FRAME    3'd1  // Edit command: frames are stored in build_frames.
`define LP_PART_PIG      3'd2
`define LP_PART_WHEEL    3'd3
`define LP_PART_ENGINE   3'd4
`define LP_PART_BOOSTER  3'd5  // Side-mounted rocket; thrust integration belongs to Role 2.
`define LP_PART_BALLOON  3'd6
`define LP_PART_FAN      3'd7  // Fan; thrust integration belongs to Role 2.

`define LP_BUILD         3'd0
`define LP_INIT_RUN      3'd1
`define LP_RUN           3'd2
`define LP_SUCCESS       3'd3
`define LP_FAIL          3'd4
`define LP_GUIDE         3'd5
`define LP_LEVEL_SELECT  3'd6
`define LP_SETTINGS      3'd7

`define LP_EDIT_PLACE    2'd0  // Includes replacement of an occupied cell.
`define LP_EDIT_REMOVE   2'd1
`define LP_EDIT_MOVE     2'd2  // Transfer from edit_source to edit_cell without charging stock.
`define LP_EDIT_RETURN   2'd3  // Return the selected source part/bundle to inventory.

`define LP_BUILD_OK             4'd0
`define LP_BUILD_ERR_PIG        4'd1
`define LP_BUILD_ERR_ATTACHMENT 4'd2
`define LP_BUILD_ERR_INVENTORY  4'd3

// Temporary construction feedback; zero returns to the overall build status.
`define LP_FEEDBACK_NONE          3'd0
`define LP_FEEDBACK_PLACED        3'd1
`define LP_FEEDBACK_REMOVED       3'd2
`define LP_FEEDBACK_NO_STOCK      3'd3
`define LP_FEEDBACK_NEED_FRAME    3'd4
`define LP_FEEDBACK_FRAME_ABOVE   3'd5
`define LP_FEEDBACK_FRAME_BELOW   3'd6
`define LP_FEEDBACK_OCCUPIED      3'd7

// Increasing IDs also give the sound priority; NONE is silence.
`define LP_SOUND_NONE       3'd0
`define LP_SOUND_TEST       3'd1
`define LP_SOUND_LAUNCH     3'd2
`define LP_SOUND_POP        3'd3
`define LP_SOUND_COLLISION  3'd4
`define LP_SOUND_EXPLOSION  3'd5
`define LP_SOUND_SUCCESS    3'd6
`define LP_SOUND_FAILURE    3'd7

// Levels: Role 4 selects one in BUILD and holds it through the run.
`define LP_LEVEL_COUNT   2
`define LP_LEVEL_BITS    2

// Block-RAM maps in level_map: one 3-bit class per world pixel. Sky and cave background are
// open; the other classes are solid. Map 0 is Cave Arch (level 3), address {y[8:0], x[8:0]};
// map 1 is Cave Flight (level 4, a flying level), address {y[7:0], x[9:0]}.
`define LP_MAP_WIDTH     478
`define LP_MAP_HEIGHT    291
// Cave Arch world size once level_map shows it twice as large (map 478 by 291).
`define LP_MAP_WORLD_WIDTH  956
`define LP_MAP_WORLD_HEIGHT 582
`define LP_FLIGHT_WIDTH  890
`define LP_FLIGHT_HEIGHT 213
`define LP_MAP_SKY       3'd0
`define LP_MAP_CAVE      3'd1
`define LP_MAP_ROCK      3'd2
`define LP_MAP_GRASS     3'd3
`define LP_MAP_ROAD      3'd4
`define LP_MAP_DARK      3'd5
`define LP_MAX_TNT       4   // Each TNT is {y[7:0], x[7:0]}; an 8 by 8 pixel block.
`define LP_TNT_PIXELS    8
`define LP_TNT_BITS      64
`define LP_MAX_HAZARDS   2   // Same {height, width, y, x} packing as terrain.
`define LP_HAZARD_BITS   64

// Left OLED MAP button, clicked in BUILD; x=[78,96), y=[55,64).
`define LP_LEVEL_BUTTON_X 78
`define LP_LEVEL_BUTTON_Y 55
`define LP_LEVEL_BUTTON_W 18
`define LP_LEVEL_BUTTON_H 9

// Left OLED boost button, clicked in RUN; x=[56,72), y=[36,52).
`define LP_BOOST_BUTTON_X 56
`define LP_BOOST_BUTTON_Y 32
`define LP_BOOST_BUTTON_W 39
`define LP_BOOST_BUTTON_H 10

// Why the last run failed; checked in this priority order.
`define LP_FAIL_NONE     2'd0
`define LP_FAIL_PIG      2'd1
`define LP_FAIL_HAZARD   2'd2
`define LP_FAIL_BOUNDS   2'd3

`endif
