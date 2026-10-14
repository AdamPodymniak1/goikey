// generated: Keccak-f[1600] round constants
function [63:0] keccak_rc(input [4:0] r);
  case (r)
    5'd0: keccak_rc = 64'h0000000000000001;
    5'd1: keccak_rc = 64'h0000000000008082;
    5'd2: keccak_rc = 64'h800000000000808a;
    5'd3: keccak_rc = 64'h8000000080008000;
    5'd4: keccak_rc = 64'h000000000000808b;
    5'd5: keccak_rc = 64'h0000000080000001;
    5'd6: keccak_rc = 64'h8000000080008081;
    5'd7: keccak_rc = 64'h8000000000008009;
    5'd8: keccak_rc = 64'h000000000000008a;
    5'd9: keccak_rc = 64'h0000000000000088;
    5'd10: keccak_rc = 64'h0000000080008009;
    5'd11: keccak_rc = 64'h000000008000000a;
    5'd12: keccak_rc = 64'h000000008000808b;
    5'd13: keccak_rc = 64'h800000000000008b;
    5'd14: keccak_rc = 64'h8000000000008089;
    5'd15: keccak_rc = 64'h8000000000008003;
    5'd16: keccak_rc = 64'h8000000000008002;
    5'd17: keccak_rc = 64'h8000000000000080;
    5'd18: keccak_rc = 64'h000000000000800a;
    5'd19: keccak_rc = 64'h800000008000000a;
    5'd20: keccak_rc = 64'h8000000080008081;
    5'd21: keccak_rc = 64'h8000000000008080;
    5'd22: keccak_rc = 64'h0000000080000001;
    5'd23: keccak_rc = 64'h8000000080008008;
    default: keccak_rc = 64'h0;
  endcase
endfunction
// rotation offsets, lane index = x + 5*y
function [5:0] keccak_rot(input [4:0] i);
  case (i)
    5'd0: keccak_rot = 6'd0;
    5'd1: keccak_rot = 6'd1;
    5'd2: keccak_rot = 6'd62;
    5'd3: keccak_rot = 6'd28;
    5'd4: keccak_rot = 6'd27;
    5'd5: keccak_rot = 6'd36;
    5'd6: keccak_rot = 6'd44;
    5'd7: keccak_rot = 6'd6;
    5'd8: keccak_rot = 6'd55;
    5'd9: keccak_rot = 6'd20;
    5'd10: keccak_rot = 6'd3;
    5'd11: keccak_rot = 6'd10;
    5'd12: keccak_rot = 6'd43;
    5'd13: keccak_rot = 6'd25;
    5'd14: keccak_rot = 6'd39;
    5'd15: keccak_rot = 6'd41;
    5'd16: keccak_rot = 6'd45;
    5'd17: keccak_rot = 6'd15;
    5'd18: keccak_rot = 6'd21;
    5'd19: keccak_rot = 6'd8;
    5'd20: keccak_rot = 6'd18;
    5'd21: keccak_rot = 6'd2;
    5'd22: keccak_rot = 6'd61;
    5'd23: keccak_rot = 6'd56;
    5'd24: keccak_rot = 6'd14;
    default: keccak_rot = 6'd0;
  endcase
endfunction
