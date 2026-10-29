// Shared terrain-following rotation. Include once inside each module body;
// these functions deliberately have no include guard (like part_sprites.vh).
// Tilt is signed -4..4 in 11.25 degree steps; positive is clockwise (y down).
function signed [3:0] sanitize_tilt;
    input signed [3:0] tilt;
    begin
        case (tilt)
            -4'sd4, -4'sd3, -4'sd2, -4'sd1,
             4'sd0,  4'sd1,  4'sd2,  4'sd3, 4'sd4: sanitize_tilt=tilt;
            default: sanitize_tilt=4'sd0;
        endcase
    end
endfunction

// Half-extent of the inverse-raster square in Q12.8, rounded outward by
// less than one fixed-point unit. Quantized sine/cosine are not exactly a
// unit vector, so 12*(cos+abs(sin)) alone is not the inverse-map extent.
function signed [15:0] rotation_extent;
    input signed [3:0] tilt;
    begin
        case (sanitize_tilt(tilt))
            -4'sd1, 4'sd1: rotation_extent=16'sd3614;
            -4'sd2, 4'sd2: rotation_extent=16'sd4006;
            -4'sd3, 4'sd3: rotation_extent=16'sd4261;
            -4'sd4, 4'sd4: rotation_extent=16'sd4345;
            default: rotation_extent=16'sd3072;
        endcase
    end
endfunction

function signed [15:0] rotation_cos;
    input signed [3:0] tilt;
    begin
        case (sanitize_tilt(tilt))
            -4'sd1, 4'sd1: rotation_cos=16'sd251;
            -4'sd2, 4'sd2: rotation_cos=16'sd237;
            -4'sd3, 4'sd3: rotation_cos=16'sd213;
            -4'sd4, 4'sd4: rotation_cos=16'sd181;
            default: rotation_cos=16'sd256;
        endcase
    end
endfunction

function signed [15:0] rotation_sin;
    input signed [3:0] tilt;
    begin
        case (sanitize_tilt(tilt))
            -4'sd4: rotation_sin=-16'sd181;
            -4'sd3: rotation_sin=-16'sd142;
            -4'sd2: rotation_sin=-16'sd98;
            -4'sd1: rotation_sin=-16'sd50;
             4'sd1: rotation_sin=16'sd50;
             4'sd2: rotation_sin=16'sd98;
             4'sd3: rotation_sin=16'sd142;
             4'sd4: rotation_sin=16'sd181;
            default: rotation_sin=16'sd0;
        endcase
    end
endfunction

function signed [3:0] slope_to_tilt;
    input signed [7:0] slope;
    reg [7:0] magnitude;
    reg signed [3:0] angle;
    begin
        // Only the supported Q4.4 gradient range is an orientation target.
        // Unknown or disconnected legacy inputs also produce a level body.
        magnitude=0; angle=0;
        if (slope >= -8'sd16 && slope <= 8'sd16) begin
            magnitude=slope < 0 ? -slope : slope;
            if (magnitude >= 14) angle=4'sd4;
            else if (magnitude >= 9) angle=4'sd3;
            else if (magnitude >= 5) angle=4'sd2;
            else if (magnitude >= 2) angle=4'sd1;
            slope_to_tilt=slope < 0 ? -angle : angle;
        end else slope_to_tilt=0;
    end
endfunction
