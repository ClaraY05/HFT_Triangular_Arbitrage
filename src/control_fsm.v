`timescale 1ns/1ps
// control_fsm.v -- sequencer: pulses 'run' for one cycle when a matrix is
// buffered, waits for fw_done, then re-arms on the next buf_ready.
module control_fsm (
    input  wire clk,
    input  wire rst,
    input  wire buf_ready,   // one-cycle pulse from matrix_buffer
    input  wire fw_done,     // one-cycle pulse from fw_engine
    output reg  run          // one-cycle pulse to fw_engine
);

localparam S_IDLE = 2'd0,
           S_LOAD = 2'd1,
           S_RUN  = 2'd2,
           S_DONE = 2'd3;

reg [1:0] state;

always @(posedge clk) begin
    run <= 1'b0;

    if (rst) begin
        state <= S_IDLE;
    end else begin
        case (state)

            S_IDLE: begin
                if (buf_ready) state <= S_LOAD;
            end

            S_LOAD: begin
                run   <= 1'b1;
                state <= S_RUN;
            end

            S_RUN: begin
                if (fw_done) state <= S_DONE;
            end

            S_DONE: begin
                if (buf_ready) state <= S_LOAD;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
