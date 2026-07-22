# 🚀 UART FIFO Module with SystemVerilog OOP Testbench

![Verilog](https://img.shields.io/badge/Language-Verilog_2001-blue.svg)
![SystemVerilog](https://img.shields.io/badge/Testbench-SystemVerilog_OOP-orange.svg)
![EDA](https://img.shields.io/badge/EDA-Xilinx_Vivado-red.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

A high-reliability **UART (Universal Asynchronous Receiver-Transmitter) Transceiver with Dual FIFO Buffers** implemented in Verilog HDL, accompanied by a comprehensive **SystemVerilog OOP & Assertion-Based Verification Environment**.

---

## 📌 Features

- **Full-Duplex UART Loopback Architecture**: Simultaneous transmission and reception processing using dedicated RX/TX FIFO buffers.
- **Configurable Baud Tick Generator**: Defaults to **9600 Baud @ 100 MHz System Clock** (with 16x oversampling).
- **Circular FIFO Memory Buffer**: Parameterized depth (`DEPTH=4`, `BIT_WIDTH=8`) with write/read pointer management and `full`/`empty` status flags.
- **Oversampled RX Sampler**: 8-tick start bit center alignment + 16-tick per data bit oversampling for robust noise rejection.
- **SystemVerilog Verification Suite**:
  - Class-based OOP Environment (Transaction, Generator, Driver, Monitor, Scoreboard, Environment).
  - Mailbox-based Inter-component Communication.
  - SVA (SystemVerilog Assertions) for reset state and baud tick timing checks.
  - Random data generation & artificial timing error injection for stress testing.

---

## 🏗 System Architecture

```
                      +-----------------------------------------------------+
                      |                      UART TOP                       |
                      |                                                     |
                      |   +--------------+        +--------------------+    |
     uart_rx -------->|==>|   UART RX    |=======>|   RX FIFO (fifo)   |    |
                      |   +--------------+        +--------------------+    |
                      |          ^                          ||              |
                      |          | b_tick                   \/              |
                      |   +--------------+        +--------------------+    |
                      |   | BAUD TICKGEN |        |   TX FIFO (fifo)   |    |
                      |   +--------------+        +--------------------+    |
                      |          | b_tick                   ||              |
                      |          v                          \/              |
                      |   +--------------+                  ||              |
     uart_tx <--------|===|   UART TX    |<===================+              |
                      |   +--------------+                                  |
                      +-----------------------------------------------------+
```

---

## 📂 Repository Structure

```
UART_FIFO/
├── 📄 README.md                        # Documentation
├── 📄 .gitignore                       # Git ignore rules for Vivado
├── 📁 20260213_uart_fifo.xpr           # Xilinx Vivado Project File
└── 📁 20260213_uart_fifo.srcs/
    ├── 📁 sources_1/imports/new/
    │   ├── 📄 uart_top.v               # Top-level UART Loopback module
    │   └── 📄 fifo.v                   # Parameterized FIFO & Control Unit
    └── 📁 sim_1/
        ├── 📁 new/
        │   └── 📄 tb_uart_sv.sv        # SystemVerilog OOP Testbench & Assertions
        └── 📁 imports/new/
            └── 📄 tb_uart_loop_back.v  # Verilog Loopback Testbench
```

---

## ⚙️ Module Descriptions

| Module | File | Description |
| :--- | :--- | :--- |
| **`uart_top`** | `uart_top.v` | Integrates `baud_tickgen`, `uart_rx`, `uart_tx`, `U_FIFO_RX`, and `U_FIFO_TX`. |
| **`uart_rx`** | `uart_top.v` | FSM-based UART receiver with 16x baud oversampling and 8-bit output deserializer. |
| **`uart_tx`** | `uart_top.v` | FSM-based UART transmitter converting 8-bit parallel FIFO output to serial TX output. |
| **`baud_tickgen`** | `uart_top.v` | Generates 16x baud rate clock ticks (`b_tick`) from 100MHz system clock. |
| **`fifo`** | `fifo.v` | Top-level circular FIFO wrapper connecting `register_file` and `control_unit`. |
| **`register_file`** | `fifo.v` | Dual-port RAM array storage for FIFO entries. |
| **`control_unit`** | `fifo.v` | Pointer management (`wptr`, `rptr`) and status generation (`full`, `empty`). |

---

## 🧪 Verification Environment (SystemVerilog OOP)

The SystemVerilog testbench ([`tb_uart_sv.sv`](file:///c:/ondevice2026_kang/class/verilog_file/20260213_uart_fifo/20260213_uart_fifo.srcs/sim_1/new/tb_uart_sv.sv)) implements an advanced Verification Component (UVM-like structure):

- **`transaction`**: Data packet definition with randomized input and error rate constraints.
- **`generator`**: Creates random test vectors and sends them via Mailbox.
- **`driver`**: Drives serial signals onto `uart_rx` with optional baud-rate jitter/error injection.
- **`monitor`**: Samples output `uart_tx` signals and reconstructs received byte frames.
- **`scoreboard`**: Compares expected vs. actual data frames and reports PASS/FAIL statistics.
- **`assertions`**:
  - `Preset_check`: Verifies `rx_data` reset behavior.
  - `B_TICK_check`: Verifies `b_tick` timing consistency.

---

## 💻 How to Run (Vivado)

1. **Open Project in Vivado**:
   ```bash
   vivado 20260213_uart_fifo.xpr
   ```
2. **Run Behavioral Simulation**:
   - Set `tb_uart_sv` as the top module in **Simulation Sources**.
   - Click **Run Simulation -> Run Behavioral Simulation**.
3. **Check Tcl Console Output**:
   ```text
   ===========================================================
     Test Completed!
     try: 100, pass : 100 , fail : 0 
   ===========================================================
   ```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for details.