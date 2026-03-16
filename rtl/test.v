module Shift_register #(parameter N = 4)
(
input wire clk,
input wire rst_n,
input wire data_i,
input wire shift_right, // 1 = shift right 0 = left
input wire [N-1:0] data_load,
input wire data_load_en,
output wire data_o
);
	reg [N-1:0] mem;
reg out_mem;
assign data_o = out_mem;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			out_mem <= 0;
			mem <= 0;
		end
		else if(data_load_en) begin
			if(shift_right) begin
				out_mem <= mem[N-1];
			end else begin
				out_mem <= mem[0];
			end
			mem <= data_load;
end
		else if(shift_right) begin
			out_mem <= mem[N-1];
			for (integer i = 0; i < N - 1; i ++) begin
				mem[N-1-i] <= mem[N-2-i];
			end
			mem[0] <= data_i;
		end
		else if(!shift_right) begin
			out_mem <= mem[0];
			for (integer i = 0; i < N - 1; i ++) begin
				mem[i] <= mem[i+1];
			end
			mem[N-1] <= data_i;
		end
end
endmodule
