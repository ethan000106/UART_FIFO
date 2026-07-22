`timescale 1ns / 1ps


module tb_uart_loop_back ();

    // loppback 검사

    // parameter BIT_PERIOD = 104_160;       //9600초니까, microsec

    parameter BAUD = 9600;
    parameter BAUD_PERIOD = (100_000_000 / BAUD) * 10;       //1클럭이 10ns니까 10을 곱해줌

    reg clk, reset, rx;
    wire tx;
    reg [7:0] test_data;  // 우리가 만든것
    integer i = 0, j = 0;



    uart_top DUT (
        .clk(clk),
        .reset(reset),
        .uart_rx(rx),
        .uart_tx(tx)



    );

    always #5 clk = ~clk;
    // function 과 task

    task uart_sender();
        begin
            rx = 0;  //rx인지
            #(BAUD_PERIOD);
            //data
            for (
                i = 0; i < 8; i = i + 1
            ) begin  // data값 8개 넣어주고 돌림
                rx = test_data[i];
                #(BAUD_PERIOD);
            end

            rx = 1'b1;  // stop
            #(BAUD_PERIOD);
            // rx = 0;


        end
    endtask




    initial begin
        #0;
        clk = 0;
        reset = 1;
        rx = 1'b1;
        test_data = 8'h31;  // ASCII = 1             testbench가 PC역할을 함
        #20;
        repeat (5) @(posedge clk);  // 상승엣지 5번을 반복해라
        reset = 0;
        repeat (5) @(posedge clk);

        uart_sender();
        // uart test pattern

        /*   for (j = 0; j < 10; j = j + 1) begin
            test_data = 8'h30 + j;
            uart_sender();
        end
*/
        for (j = 0; j < 12; j = j + 1) begin  // tx_data출력확인

            #(BAUD_PERIOD);
        end
        $stop;

    end



endmodule
