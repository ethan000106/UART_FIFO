# UART_FIFO

UART FIFO Verilog Implementation & SystemVerilog Testbench for Vivado.

## Project Structure
- `20260213_uart_fifo.xpr`: Vivado Project File
- `20260213_uart_fifo.srcs/sources_1/imports/new/`:
  - `uart_top.v`: UART Top-level module (combines UART TX, RX, Baud tick generator, and FIFO)
  - `fifo.v`: Circular FIFO Buffer module
- `20260213_uart_fifo.srcs/sim_1/`:
  - `tb_uart_sv.sv`: SystemVerilog Testbench with Interface, Generator, Driver, Monitor, Scoreboard, and Environment
  - `tb_uart_loop_back.v`: Verilog loopback testbench