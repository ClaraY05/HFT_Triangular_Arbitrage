`timescale 1ns/1ps
module fw_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        run,
    output reg  [3:0]  mat_addr,
    input  wire [31:0] mat_data,
    output reg         done,
    output wire [31:0] diag0,
    output wire [31:0] diag1,
    output wire [31:0] diag2,
    output wire [31:0] diag3,
    output reg  [15:0] loop_mask
);

reg signed [31:0] dist [0:15];

localparam S_IDLE = 2'd0,
           S_LOAD = 2'd1,
           S_COMP = 2'd2,
           S_DONE = 2'd3;

reg [1:0]  state;
reg [4:0]  load_cnt;
reg [1:0]  k, i, j;
reg signed [31:0] through;

reg [1:0]         best_idx;
reg signed [31:0] best_val;
integer           mi, ni;

always @(posedge clk) begin
    done <= 1'b0;

    if (rst) begin
        state     <= S_IDLE;
        load_cnt  <= 0;
        loop_mask <= 16'h0000;
        mat_addr  <= 4'd0;
    end else begin
        case (state)

            S_IDLE: begin
                if (run) begin
                    load_cnt <= 5'd0;
                    mat_addr <= 4'd0;
                    state    <= S_LOAD;
                end
            end

            S_LOAD: begin
                // capture: data for addr N arrives at load_cnt = N+2
                if (load_cnt >= 5'd2 && load_cnt <= 5'd17)
                    dist[load_cnt - 2] <= $signed(mat_data);

                if (load_cnt == 5'd18) begin
                    k     <= 2'd0;
                    i     <= 2'd0;
                    j     <= 2'd0;
                    state <= S_COMP;
                end else begin
                    // issue next address, hold at 15 once reached
                    mat_addr <= (load_cnt < 5'd15) ? load_cnt[3:0] + 1 : 4'd15;
                    load_cnt <= load_cnt + 1;
                end
            end

            S_COMP: begin
                through = $signed(dist[{i, k}]) + $signed(dist[{k, j}]);
                if (through < $signed(dist[{i, j}]))
                    dist[{i, j}] <= through;

                if (j == 2'd3) begin
                    j <= 2'd0;
                    if (i == 2'd3) begin
                        i <= 2'd0;
                        if (k == 2'd3)
                            state <= S_DONE;
                        else
                            k <= k + 1;
                    end else
                        i <= i + 1;
                end else
                    j <= j + 1;
            end

            S_DONE: begin
                done <= 1'b1;

                best_val = 32'sh7FFF_FFFF;
                best_idx = 2'd0;
                if ($signed(dist[0])  < best_val) begin best_val = dist[0];  best_idx = 2'd0; end
                if ($signed(dist[5])  < best_val) begin best_val = dist[5];  best_idx = 2'd1; end
                if ($signed(dist[10]) < best_val) begin best_val = dist[10]; best_idx = 2'd2; end
                if ($signed(dist[15]) < best_val) begin best_val = dist[15]; best_idx = 2'd3; end

                loop_mask <= 16'h0000;
                if (best_val < 0) begin
                    for (mi = 0; mi < 4; mi = mi + 1)
                        loop_mask[best_idx * 4 + mi] <= 1'b1;
                    for (ni = 0; ni < 4; ni = ni + 1)
                        loop_mask[ni * 4 + best_idx] <= 1'b1;
                end

                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

assign diag0 = dist[0];
assign diag1 = dist[5];
assign diag2 = dist[10];
assign diag3 = dist[15];

endmodule