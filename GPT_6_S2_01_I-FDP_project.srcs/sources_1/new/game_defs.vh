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

// Cell size and movement format are provisional starting values.
`define LP_CELL_PIXELS   8
`define LP_COORD_BITS    16
`define LP_FRAC_BITS     8
`define LP_MAX_TERRAIN   4
`define LP_RECT_BITS     32

`define LP_PART_EMPTY    3'd0
`define LP_PART_FRAME    3'd1  // Edit command: frames are stored in build_frames.
`define LP_PART_PIG      3'd2
`define LP_PART_WHEEL    3'd3
`define LP_PART_ENGINE   3'd4
`define LP_PART_BOOSTER  3'd5  // Reserved ID; boost is planned as an engine ability.
`define LP_PART_BALLOON  3'd6

`define LP_BUILD         3'd0
`define LP_INIT_RUN      3'd1
`define LP_RUN           3'd2
`define LP_SUCCESS       3'd3
`define LP_FAIL          3'd4
`define LP_GUIDE         3'd5

`define LP_EDIT_PLACE    2'd0  // Includes replacement of an occupied cell.
`define LP_EDIT_REMOVE   2'd1

`define LP_BUILD_OK             4'd0
`define LP_BUILD_ERR_PIG        4'd1
`define LP_BUILD_ERR_ATTACHMENT 4'd2
`define LP_BUILD_ERR_INVENTORY  4'd3

`endif
