`timescale 1ns / 1ps

interface uart_fifo_interface (
    input logic clk
);

    logic reset;
    logic uart_rx;
    logic uart_tx;
    logic [7:0] rx_data;
    logic rx_done;
    logic b_tick;

    property Preset_check;
        @(posedge clk) reset |=> (rx_data == 0);
    endproperty
    reg_reset_check :
    assert property (Preset_check)
    else $display("%t : Assert error : reset check", $time);


    property B_TICK_check;
        @(posedge clk) disable iff (reset) b_tick |-> ##(10416) b_tick;
    endproperty
    reg_b_tick_check :
    assert property (B_TICK_check)
    else $display("%t : Assert error : b_tick check", $time);




endinterface  //uart_fifo_interface




class transaction;

    rand bit uart_rx;
    rand logic [7:0] tx_data;
    logic clk;
    logic reset;
    logic uart_tx;
    logic [7:0] rx_data;
    logic rx_done;

    rand int error_cnt;

    constraint c_error {
        error_cnt >= -4;
        error_cnt <= 4;
    }

    function void display(string name);
        $display("%t : [%s] input = %0d, output = %0d, (Error Rate: %2d%%)",
                 $time, name, tx_data, rx_data, error_cnt);
    endfunction  //new()

endclass  //transaction


class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_ev;

    function new(mailbox#(transaction) gen2drv_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_ev);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction  //new()


    task run(int run_count);
        repeat (run_count) begin
            tr = new();
            tr.randomize();
            //tr.tx_data = 8'hA5;
            gen2drv_mbox.put(tr);
            gen2scb_mbox.put(tr);
            tr.display("gen");
            @(gen_next_ev);
        end
    endtask  //run
endclass  //generator

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_fifo_interface uf_if;
    int i;
    int baud_tick = 10416;
    int current_tick;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_fifo_interface uf_if);
        this.gen2drv_mbox = gen2drv_mbox;
        this.uf_if = uf_if;
    endfunction  //new()


    task preset();
        uf_if.reset   = 1;
        uf_if.uart_rx = 1;
        @(negedge uf_if.clk);
        @(negedge uf_if.clk);
        uf_if.reset   = 0;
        uf_if.uart_rx = 0;
        @(negedge uf_if.clk);


    endtask  //preset

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            current_tick = baud_tick + (baud_tick * tr.error_cnt / 100);
            @(posedge uf_if.clk);
            #1;
            uf_if.uart_rx <= 0;
            repeat (current_tick) @(posedge uf_if.clk);
            for (i = 0; i < 8; i++) begin
                uf_if.uart_rx <= tr.tx_data[i];
                repeat (current_tick) @(posedge uf_if.clk);
            end
            uf_if.uart_rx <= 1;
            repeat (current_tick) @(posedge uf_if.clk);
            tr.display("drv");

        end

    endtask  //run

endclass  //driver

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual uart_fifo_interface uf_if;
    int i;
    int baud_tick = 10416;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_fifo_interface uf_if);
        this.mon2scb_mbox = mon2scb_mbox;
        this.uf_if = uf_if;

    endfunction  //new()
    task run();

        forever begin
            tr = new();
            fork
                begin : wait_for_data
                    wait (uf_if.uart_tx == 0);
                end
                begin : watchdog_timer
                    #50000000 $display("\n[CONER CASE]");
                    $stop;
                end
            join_any
            disable fork;
            repeat (baud_tick / 2) @(posedge uf_if.clk);
            for (i = 0; i < 8; i++) begin
                repeat (baud_tick) @(posedge uf_if.clk);
                tr.rx_data[i] = uf_if.uart_tx;
            end
            repeat (baud_tick) @(posedge uf_if.clk);
            mon2scb_mbox.put(tr);
            tr.display("mon");


        end
    endtask  //run
endclass  //monitor

class scoreboard;

    transaction                  mon_tr;
    transaction                  gen_tr;  //exp_tr

    mailbox #(transaction)       mon2scb_mbox;
    mailbox #(transaction)       gen2scb_mbox;
    event                        gen_next_ev;

    logic                  [7:0] expected_queue   [$:16];
    int                          pass_cnt,                fail_cnt, try_cnt;


    function new(mailbox#(transaction) mon2scb_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_ev);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_ev  = gen_next_ev;
    endfunction  //new()
    task run();
        fork
            forever begin
                gen2scb_mbox.get(gen_tr);
                expected_queue.push_back(gen_tr.tx_data);
            end
            forever begin
                mon2scb_mbox.get(mon_tr);
                mon_tr.display("scb");

                if (expected_queue.size() > 0) begin
                    logic [7:0] expected_data = expected_queue.pop_front();
                    try_cnt++;
                    if (expected_data == mon_tr.rx_data) begin
                        $display("%t : PASS, GEN_DATA : %h,MON_DATA : %h ",
                                 $time, expected_data, mon_tr.rx_data);
                        pass_cnt++;
                    end else begin
                        $display("%t : FAIL, GEN_DATA : %h,MON_DATA : %h ",
                                 $time, expected_data, mon_tr.rx_data);
                        fail_cnt++;
                    end
                end else begin
                    $display("%t : ERROR, Expected Queue is empty", $time);
                end
                ->gen_next_ev;
            end
        join
    endtask  //run
endclass  //scoreboard

/* 원래 내 코드
class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    virtual uart_fifo_interface uf_if;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_ev;

    function new(virtual uart_fifo_interface uf_if);
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen2scb_mbox = new();
        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_ev);
        drv = new(gen2drv_mbox, uf_if);
        mon = new(mon2scb_mbox, uf_if);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_ev);

    endfunction  //new()

    task run();

        drv.preset();
        fork
            gen.run(10);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $stop;

    endtask  //run


endclass  //environment

*/
class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    virtual uart_fifo_interface uf_if;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_ev;

    function new(virtual uart_fifo_interface uf_if);
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen2scb_mbox = new();
        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_ev);
        drv = new(gen2drv_mbox, uf_if);
        mon = new(mon2scb_mbox, uf_if);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_ev);
    endfunction  //new()

    task run();
        drv.preset();

        fork
            begin
                gen.run(100);
                #50000;
                $display(
                    "\n===========================================================");
                $display("  Test Completed!");
                $display("  try: %0d, pass : %0d , fail : %0d ", scb.try_cnt,
                         scb.pass_cnt, scb.fail_cnt);
                $display(
                    "===========================================================");
                $stop;
            end

            drv.run();
            mon.run();
            scb.run();
        join_any


    endtask  //run
endclass  //environment

/*
class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    virtual uart_fifo_interface uf_if;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_ev;

    function new(virtual uart_fifo_interface uf_if);
        gen2drv_mbox = new();
        mon2scb_mbox = new();
        gen2scb_mbox = new();
        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_ev);
        drv = new(gen2drv_mbox, uf_if);
        mon = new(mon2scb_mbox, uf_if);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_ev);
    endfunction  //new()

    task run();
        drv.preset();
        
        fork
            begin 
                int baud_tick = 10416; 
                
                for (int pct = -10; pct <= 10; pct++) begin
                    
                    drv.baud_tick = baud_tick + (baud_tick * pct / 100);
                    
                    $display("\n===========================================================");
                    $display("  [test error rate] %0d%% setting (baud_tick: %0d)", pct, drv.baud_tick);
                    $display("===========================================================");
                    
                    // 해당 오차율에서 2번씩 랜덤 데이터를 쏴서 테스트
                    // transaction에서 constraints로도 해보기
                    gen.run(10); 
                end
                
                #50000;
                $display("\n===========================================================");
                $display("  test completed.");
                $display("===========================================================");
                $stop;
            end
            
            drv.run();
            mon.run();
            scb.run();
        join_any

    endtask  //run

endclass  //environment
*/


module tb_uart_sv ();
    logic clk;

    uart_fifo_interface uf_if (clk);
    environment env;

    uart_top dut (
        .clk(clk),
        .reset(uf_if.reset),
        .uart_rx(uf_if.uart_rx),
        .uart_tx(uf_if.uart_tx),
        .rx_data(uf_if.rx_data),
        .rx_done(uf_if.rx_done)

    );
    assign uf_if.b_tick = dut.w_b_tick;

    always #5 clk = ~clk;
    initial begin
        clk = 0;
        env = new(uf_if);
        env.run();
        //force dut.w_tx_busy = 1'b1;
        // force uf_if.rx_data = 8'hFF;
    end
    /*
    initial begin
        #10000;
        force dut.w_b_tick = 1'b1;
        #10;
        release dut.w_b_tick;
    end
*/




endmodule
