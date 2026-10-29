// Shared terrain-following rotation. Include once inside each module body;
// these functions deliberately have no include guard (like part_sprites.vh).
// Tilt is signed -16..15 in 11.25 degree steps; positive is clockwise (y down).
// -16 (180 degrees) is upside down. Every value of the LP_TILT_BITS field is a
// valid angle, so sanitize_tilt only normalises the width.
function signed [`LP_TILT_BITS-1:0] sanitize_tilt;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        sanitize_tilt=tilt;
    end
endfunction

// Step within a quarter turn, folded to 0..4: angles r and 8-r differ only by
// swapping |cos| and |sin|, so their extents and basis lengths match.
function [2:0] quarter_fold;
    input signed [`LP_TILT_BITS-1:0] tilt;
    reg [2:0] r;
    begin
        r=tilt[2:0];
        quarter_fold=r>4 ? 4'd8-r : r;
    end
endfunction

// cos(r * 11.25 degrees) in Q8 for r = 0..8; sin(r) is quarter_cos(8-r).
function signed [9:0] quarter_cos;
    input [3:0] r;
    begin
        case (r)
            0: quarter_cos=256; 1: quarter_cos=251; 2: quarter_cos=237;
            3: quarter_cos=213; 4: quarter_cos=181; 5: quarter_cos=142;
            6: quarter_cos=98;  7: quarter_cos=50;  default: quarter_cos=0;
        endcase
    end
endfunction

// Half-extent of the inverse-raster square in Q12.8, rounded outward by
// less than one fixed-point unit. Quantized sine/cosine are not exactly a
// unit vector, so 12*(|cos|+|sin|) alone is not the inverse-map extent.
function signed [15:0] rotation_extent;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        case (quarter_fold(tilt))
            1: rotation_extent=16'sd3614;
            2: rotation_extent=16'sd4006;
            3: rotation_extent=16'sd4261;
            4: rotation_extent=16'sd4345;
            default: rotation_extent=16'sd3072;
        endcase
    end
endfunction

// Quadrants of the 32-step turn: tilt[4:3] picks the quadrant, tilt[2:0] the step.
function signed [15:0] rotation_cos;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        case (tilt[4:3])
            2'd0: rotation_cos=quarter_cos(tilt[2:0]);
            2'd1: rotation_cos=-quarter_cos(4'd8-tilt[2:0]);
            2'd2: rotation_cos=-quarter_cos(tilt[2:0]);
            default: rotation_cos=quarter_cos(4'd8-tilt[2:0]);
        endcase
    end
endfunction

function signed [15:0] rotation_sin;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        case (tilt[4:3])
            2'd0: rotation_sin=quarter_cos(4'd8-tilt[2:0]);
            2'd1: rotation_sin=quarter_cos(tilt[2:0]);
            2'd2: rotation_sin=-quarter_cos(4'd8-tilt[2:0]);
            default: rotation_sin=-quarter_cos(tilt[2:0]);
        endcase
    end
endfunction

// Squared Q8 basis length. Used to test individual inverse-raster cells
// without division; the rounded sine/cosine are not exactly unit length.
function signed [17:0] rotation_norm_squared;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        case (quarter_fold(tilt))
            1: rotation_norm_squared=18'sd65501;
            2: rotation_norm_squared=18'sd65773;
            3: rotation_norm_squared=18'sd65533;
            4: rotation_norm_squared=18'sd65522;
            default: rotation_norm_squared=18'sd65536;
        endcase
    end
endfunction

// More than a quarter turn from upright: the top row faces the ground.
function tilt_flipped;
    input signed [`LP_TILT_BITS-1:0] tilt;
    begin
        tilt_flipped=tilt>8 || tilt<-8;
    end
endfunction

function signed [`LP_TILT_BITS-1:0] slope_to_tilt;
    input signed [7:0] slope;
    reg [7:0] magnitude;
    reg signed [`LP_TILT_BITS-1:0] angle;
    begin
        // Only the supported Q4.4 gradient range is an orientation target.
        // Unknown or disconnected legacy inputs also produce a level body.
        magnitude=0; angle=0;
        if (slope >= -8'sd16 && slope <= 8'sd16) begin
            magnitude=slope < 0 ? -slope : slope;
            if (magnitude >= 14) angle=4;
            else if (magnitude >= 9) angle=3;
            else if (magnitude >= 5) angle=2;
            else if (magnitude >= 2) angle=1;
            slope_to_tilt=slope < 0 ? -angle : angle;
        end else slope_to_tilt=0;
    end
endfunction
