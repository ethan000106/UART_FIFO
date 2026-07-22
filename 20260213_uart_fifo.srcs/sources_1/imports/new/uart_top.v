`timescale 1ns / 1ps

module uart_top (
    input clk,
    input reset,
    // input  btn_down,  //tx_start
    input uart_rx,  // rx로 값을 받아
    // 추가 포트 for sender
   // input i_tx_start,
   // input [7:0] i_tx_data,
   // output o_tx_busy,

    output uart_tx,             // tx로 값을 내보내는 loopback 구조를 만들거다.
    output [7:0] rx_data,
    output rx_done

);
    wire w_b_tick, w_rx_done;
    wire [7:0] w_rx_data, w_rx_fifo_pop_data,w_tx_fifo_pop_data;
    wire w_tx_busy;
    wire w_tx_done;
    wire w_tx_fifo_full, w_rx_fifo_empty,w_tx_fifo_empty;
    assign rx_data = w_rx_data;
    assign rx_done = w_rx_done;



    /* btn_debounce U_BD_TX_START (
        .clk  (clk),
        .reset(rst),
        .i_btn(btn_down),
        .o_btn(w_tx_start)
    );

*/


    uart_tx U_UART_TX (
        .clk     (clk),
        .reset     (reset),
        .b_tick  (w_b_tick),
        .tx_start(~w_tx_fifo_empty),
        .tx_data (w_tx_fifo_pop_data),
        .tx_busy (w_tx_busy),
        .tx_done (),
        .uart_tx (uart_tx)

    );
fifo U_FIFO_TX(

    .clk(clk),
    .reset(reset),
    .push(~w_rx_fifo_empty ),
    .pop(~w_tx_busy),
    .push_data(w_rx_fifo_pop_data),
    . pop_data(w_tx_fifo_pop_data),
    . full(w_tx_fifo_full),
    . empty(w_tx_fifo_empty)

);
fifo U_FIFO_RX(

    .clk(clk),
    .reset(reset),
    .push(w_rx_done),
    .pop(~w_tx_fifo_full),
    .push_data(w_rx_data),
    . pop_data(w_rx_fifo_pop_data),
    . full(),
    . empty(w_rx_fifo_empty)

);
    uart_rx U_UART_RX (
        .clk(clk),
        .reset(reset),
        .b_tick(w_b_tick),
        .rx(uart_rx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

    baud_tickgen U_BAUDTICK (
        .clk(clk),
        .reset(reset),
        .b_tick(w_b_tick)
    );

endmodule

module uart_rx (
    input clk,
    input reset,
    input b_tick,  // tx와 동일한 곳에서 받아온다.
    input rx,      // 외부에서 받아오는 값

    output [7:0] rx_data,  // 값을 받아 tx로 내보내는값
    output       rx_done
);


    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
    reg [1:0] c_state, n_state;  // state 4개니까 2비트 필요
    reg [4:0] b_tick_cnt_reg, b_tick_cnt_next;  //23까지 필요 -> 5비트
    reg [2:0] bit_cnt_next, bit_cnt_reg;  // 8개니까 3비트
    reg done_reg, done_next;
    reg [7:0]
        buf_reg,
        buf_next;  // 데이터를 넣어줄 공간 원리는 tx와 동일

    assign rx_data = buf_reg;  // 출력 연결
    assign rx_done = done_reg;  // 출력 연결

    // state
    always @(posedge clk, posedge reset) begin  //초기화
        if (reset) begin
            c_state        <= IDLE;
            b_tick_cnt_reg <= 5'd0;
            bit_cnt_reg    <= 3'd0;
            done_reg       <= 1'b0;
            buf_reg        <= 8'd0;
        end else begin
            c_state        <= n_state;  // 다음 상태 지정
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            done_reg       <= done_next;
            buf_reg        <= buf_next;
        end
    end

    // next CL, output

    always @(*) begin
        n_state         = c_state;  // 초기화
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        done_next       = done_reg;
        buf_next        = buf_reg;


        case (c_state)
            IDLE: begin
                done_next = 1'b0;
                b_tick_cnt_next = 5'd0;
                bit_cnt_next = 3'd0;

                if (b_tick == 1 & (! rx)) begin      // b_tick 이 1이고 rx가 0일때
                    buf_next = 8'd0;          //이제 값을 넣을거니까 초기화 해줌
                    n_state = START;
                end

            end

            START: begin
                if (b_tick == 1) begin
                    if ((b_tick_cnt_reg == 7)) begin    // 처음에만 8tick을 줘서 중간을 맞추
                        b_tick_cnt_next = 0;
                        n_state = DATA;

                        // buf_next[7] = rx;        // buf_next에 7이 들어가고 하나씩 shift

                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end

                end
            end


            DATA: begin
                if (b_tick == 1) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        buf_next = {
                            rx, buf_reg[7:1]
                        };  // 똑같이 처음 값만 들어오는 값 빼고 shift
                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end

            end

            STOP: begin
                if (b_tick == 1) begin
                    if ((b_tick_cnt_reg == 15)) begin

                        n_state   = IDLE;
                        done_next = 1'b1;

                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

        endcase



    end




endmodule






module uart_tx (
    input        clk,
    input        reset,
    input        tx_start,
    input        b_tick,    // baud_tickgen 에서 가져온 b_tick
    input  [7:0] tx_data,   // rx_data를 받아옴
    output       uart_tx,   //다시 PC로 내보낸다.
    output       tx_busy,   // data가 나가는 중이라는것을 알림
    output       tx_done    // data가 다 나갔다는것을 알림
);


    localparam IDLE = 2'd0, START = 2'd1;       // state들 fsm구조, asm chart 참고
    localparam DATA = 2'd2, STOP = 2'd3;

    // state reg
    reg [1:0] c_state, n_state;  //current_state, next_state의 준말
    reg tx_reg, tx_next;
    // feedback 구조를 만들게 하기 위해서 ,순차논리 출력을 위해서 ouput을 SL로 내보내려고
    // 새로 추가된거 bit_cnt, 조합논리에서만 값을 바꾸는 것이기 때문에 같이 feedback구조를 만들어서 하는것이 latch를 줄일수있다.
    // reg [3:0] bit_cnt;
    reg [2:0] bit_cnt_reg, bit_cnt_next;  //8개니까 8비트 선언
    // b_tick_cnt 추가
    reg [3:0]
        b_tick_cnt_reg,
        b_tick_cnt_next;          // b_tick이 16개씩 나오는것을 세야하기 때문이다.

    reg busy_reg, busy_next, done_reg, done_next;  //feedback구조를 위해 
    // busy와 done을 만드는 이유는 신호를 보내는 중에 누군가가 신호를 바꾸거나 보내면 안되기 때문이다.

    // data_in_buf
    reg [7:0] data_in_buf_reg, data_in_buf_next;
    // buf를 만드는 이유는 안정성을 위해 만든다.
    // 외부에서 오는 data가 data를 보내는 와중에 내부 data에 영향을 주면 안되기 때문이다.


    //reg [3:0] b_tick_counter;  //16tick

    //reg b_tick_15;


    assign uart_tx = tx_reg;  // loopback구조 연결
    assign tx_busy = busy_reg;  // 연결
    assign tx_done = done_reg;  // 연결


    // state tegister SL
    always @(posedge clk, posedge reset) begin          // 초기상태, 초기화를 해주고 다음상태 지정
        if (reset) begin
            c_state         <= IDLE;
            tx_reg          <= 1'b1;
            bit_cnt_reg     <= 1'b0;
            busy_reg        <= 1'b0;
            done_reg        <= 1'b0;
            data_in_buf_reg <= 8'h00;  // signed로 되면 안되니까 8'h00
            b_tick_cnt_reg  <= 4'h0;




        end else begin
            c_state         <= n_state;
            tx_reg          <= tx_next;
            bit_cnt_reg     <= bit_cnt_next;
            busy_reg        <= busy_next;
            done_reg        <= done_next;
            data_in_buf_reg <= data_in_buf_next;
            b_tick_cnt_reg  <= b_tick_cnt_next;



        end

    end

    // next_CL
    always @(*) begin  // 순차논리 fsm case문
        n_state = c_state;
        tx_next = tx_reg;
        bit_cnt_next = bit_cnt_reg;
        busy_next = busy_reg;
        done_next = done_reg;
        data_in_buf_next = data_in_buf_reg;
        b_tick_cnt_next = b_tick_cnt_reg;


        case (c_state)
            IDLE: begin
                tx_next         = 1'b1;  // 초기화
                bit_cnt_next    = 3'b0;
                b_tick_cnt_next = 4'h0;
                busy_next       = 0;
                done_next       = 0;


                if (tx_start == 1) begin
                    n_state = START;
                    busy_next = 1'b1;  // data를 내보낼것이라고 알림
                    data_in_buf_next = tx_data;     // rx data들을 buf에 담아서 tx로 보낼것이다.


                end  //else n_state = c_state;
            end


            START: begin  // start uart frame of start bit
                tx_next = 1'b0;

                if (b_tick == 1) begin
                    if (b_tick_cnt_reg == 15) begin
                        n_state = DATA;
                        b_tick_cnt_next = 4'h0;  // 0으로 초기화
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                tx_next = data_in_buf_reg[0];
                // 언제 shift하나 -> 비트 shift가 증가할때, lsb부터 송출하겠다는 의미

                if (b_tick == 1) begin
                    if (b_tick_cnt_reg == 15) begin

                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 4'h0;
                            n_state = STOP;
                        end else begin
                            b_tick_cnt_next = 4'h0;
                            bit_cnt_next = bit_cnt_reg + 1;
                            data_in_buf_next = {
                                1'b0, data_in_buf_reg[7:1]
                            };  // 들어올값 뺴고 하나씩 shift한다.
                            // data를 안전하게 밀어내기 위해 초기를 0으로 채운다.
                            n_state = DATA;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end



            STOP: begin
                tx_next = 1'b1;

                if (b_tick == 1) begin
                    if (b_tick_cnt_reg == 15) begin
                        done_next = 1'b1;
                        n_state   = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end

                end
            end




        endcase
    end

endmodule


module baud_tickgen (
    input clk,
    input reset,
    output reg b_tick
);
    parameter BAUDRATE = 9600 * 16;            // 9600당 tick이 하나씩 나오는 구조에서 16개씩 나오도록 설계
    parameter F_COUNT = 100_000_000 / BAUDRATE;         // 651일때마다 tick이 하나씩 나온다.

    reg [$clog2 (F_COUNT)-1 : 0] counter_reg;


    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            b_tick <= 0;
        end else begin
            counter_reg <= counter_reg + 1;

            if (counter_reg == (F_COUNT - 1)) begin
                counter_reg <= 0;
                b_tick <= 1;
            end else begin
                b_tick <= 0;
            end
        end
    end



endmodule

