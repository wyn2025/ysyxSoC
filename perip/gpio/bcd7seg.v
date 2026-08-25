module bcd7seg(
  input  [3:0] b,
  output reg [6:0] h
);

 always @(b)
    begin
            case(b)
                4'd0:h<=7'b000_0001;
                4'd1:h<=7'b100_1111;
                4'd2:h<=7'b001_0010;
                4'd3:h<=7'b000_0110;
                4'd4:h<=7'b100_1100;
                4'd5:h<=7'b010_0100;
                4'd6:h<=7'b010_0000;
                4'd7:h<=7'b000_1111;
                4'd8:h<=7'b000_0000;
                4'd9:h<=7'b000_0100;
                4'd10:h<=7'b111_1110;
                default:h<=7'b000_0001;
            endcase
    end
endmodule

