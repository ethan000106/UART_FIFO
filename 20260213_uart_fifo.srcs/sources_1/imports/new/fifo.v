`timescale 1ns / 1ps

module fifo #(
    parameter DEPTH = 4,
    BIT_WIDTH = 8
) (


    input clk,
    input reset,
    input push,
    input pop,
    input [7:0] push_data,
    output [7:0] pop_data,
    output full,
    output empty

);
    wire [$clog2(DEPTH)-1:0] w_wptr, w_rptr;

    register_file #(
        .DEPTH(DEPTH),
        .BIT_WIDTH(BIT_WIDTH)
    ) u_REG_FILE (
        .clk(clk),
        .push_data(push_data),
        .w_addr(w_wptr),
        .r_addr(w_rptr),
        .we(push & (~full)),
        .pop_data(pop_data)

    );
    control_unit #(
        .DEPTH(DEPTH)
    ) u_CNT (
        .clk  (clk),
        .reset(reset),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );
endmodule



module register_file #(
    parameter DEPTH = 4,
    BIT_WIDTH = 8
) (
    input clk,
    input [BIT_WIDTH-1:0] push_data,
    input [$clog2(DEPTH)-1:0] w_addr,          // 나중에 변수가 바뀔수있으니 parameter로 지정
    input [$clog2(DEPTH)-1:0] r_addr,
    input we,
    output  [BIT_WIDTH-1:0] pop_data

);

    // ram

    reg [BIT_WIDTH-1:0] register_file[0:DEPTH-1];
    // push to register file
    always @(posedge clk) begin      // 메모리는 초기화하지 않기 때문에 리셋은 없다.
        if (we) begin
            //push
            register_file[w_addr] <= push_data;
        end 
    end


     assign pop_data = register_file[r_addr];
endmodule

module control_unit #(
    parameter DEPTH = 4
) (
    input clk,
    input reset,
    input push,
    input pop,
    output [$clog2(DEPTH)-1:0] wptr,
    output [$clog2(DEPTH)-1:0] rptr,
    output full,
    output empty
);

    reg [1:0] c_state, n_state;
    reg [$clog2(DEPTH)-1:0] wptr_reg, wptr_next, rptr_reg, rptr_next;
    reg full_reg, full_next, empty_reg, empty_next;



    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state   <= 2'b00;
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            full_reg  <= 0;
            empty_reg <= 1;
        end else begin
            c_state   <= n_state;
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    // next st, output결정
    always @(*) begin
        n_state = c_state;
        wptr_next = wptr_reg;
        rptr_next = rptr_reg;
        full_next = full_reg;
        empty_next = empty_reg;
        case ({
            push, pop
        })
            // push부터
            2'b10: begin         // push와 pop의 결합연산자니가 10이면 push만 1
                if (!full) begin

                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;  // 채워졌으니 empty는 0으로
                    if (wptr_next == rptr_reg) begin   // 01230이고 0000이니까
                        full_next = 1'b1;

                    end
                end
            end
            // pop
            2'b01: begin       // pop만 1
                if (!empty) begin

                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_reg == rptr_next) begin     // 0 01230 이니까
                        empty_next = 1'b1;
                    end
                end
            end

            // push,pop 동시
            2'b11: begin             // push,pop동시          01230  01230
                if (full_reg == 1'b1) begin  // read만 증가
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;  // 제어(그냥 한번더)
                end else if (empty_reg == 1) begin  // write 만 증가
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;  // 제어(그냥 한번더)
                end else begin  // 아닐때는 각각 증가
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end


        endcase
    end
endmodule

