# 🔁 UART + FIFO Loopback — SystemVerilog Class-based Verification

[![Language](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)]()
[![EDA Tools](https://img.shields.io/badge/EDA-Xilinx%20Vivado%20(XSIM)-red.svg)]()
[![Verification](https://img.shields.io/badge/Verification-SV%20Testbench%20%2B%20SVA-purple.svg)]()

> **UART RX → FIFO → UART TX 루프백 구조를 SystemVerilog 클래스 기반 테스트벤치(Generator · Driver · Monitor · Scoreboard)와 SVA(SystemVerilog Assertion)로 검증한 프로젝트**
> 단일 데이터, 랜덤 데이터, FIFO Full, 제어 신호(reset / `b_tick`) 무결성의 4가지 시나리오를 확인했습니다.

---

## 📋 Table of Contents
1. [Block Diagram & Timing](#-block-diagram--timing)
2. [DUT Overview](#-dut-overview)
3. [Verification Scenario](#-verification-scenario)
4. [Testbench Code](#-testbench-code)
5. [Simulation](#-simulation)
6. [Troubleshooting](#-troubleshooting)

---

## 🧱 Block Diagram & Timing

`uart_rx`가 수신한 데이터를 `fifo_rx`에 저장하고, `fifo_rx`의 데이터를 `fifo_tx`를 거쳐 `uart_tx`로 다시 내보내는 **Loopback** 구조입니다. 각 FIFO의 `empty` / `full`, `uart_tx`의 `tx_busy` 신호로 push / pop과 송신 시작을 제어합니다.

<p align="center">
  <img src="docs/block_diagram.png" alt="UART FIFO block diagram" width="55%">
</p>

UART RX 입력(Start bit + D0~D7 + Stop bit)이 들어오면 `w_rx_done`과 함께 `w_rx_data`가 확정되고, FIFO를 거쳐 `uart_tx`로 동일한 데이터가 출력됩니다.

<p align="center">
  <img src="docs/timing_diagram.png" alt="UART RX to TX loopback timing" width="90%">
</p>

* UART는 **LSB first**로 전송합니다. 예를 들어 `0x31 (0011_0001)`은 선로에 `1000_1100` 순서로 나갑니다.
* 100 MHz 클럭, **9600 baud**, **16배 오버샘플링** 구조입니다. `baud_tickgen`이 651클럭(= 100,000,000 / (9600 × 16))마다 `b_tick`을 내고, 1비트는 16 tick(= 651 × 16 = 10,416클럭)입니다. 테스트벤치의 `baud_tick = 10416`이 이 1비트 구간에 해당합니다.

<p align="center">
  <img src="docs/tb_wave_overview.png" alt="Testbench waveform: 0x31 transmitted LSB first" width="85%">
</p>
<p align="center">
  <img src="docs/tb_wave_zoom.png" alt="Zoomed waveform of rx data passing through FIFO" width="85%">
</p>

---

## 🔩 DUT Overview

| 모듈 | 역할 |
| :--- | :--- |
| `uart_top` | 최상위. `uart_rx → fifo_rx → fifo_tx → uart_tx` 루프백을 구성하고 `rx_data`, `rx_done`을 외부로 출력 |
| `baud_tickgen` | `9600 × 16` 기준 `b_tick` 생성 (`F_COUNT = 100_000_000 / (9600 × 16) = 651`클럭마다 1 tick) |
| `uart_rx` | FSM `IDLE → START → DATA → STOP`. Start bit 감지 후 **8 tick**을 세어 비트 중앙에 맞추고, 이후 **16 tick마다** 1비트를 샘플링해 `buf_reg`에 LSB부터 shift-in. 수신이 끝나면 `rx_done` 출력 |
| `uart_tx` | FSM `IDLE → START → DATA → STOP`. `tx_start`가 오면 `tx_data`를 내부 버퍼에 잡아두고(`busy` 표시), 비트당 16 tick씩 LSB부터 송출 |
| `fifo` | `DEPTH = 4`, `BIT_WIDTH = 8`. `register_file`(저장소, 리셋 없음)과 `control_unit`(`wptr` / `rptr` / `full` / `empty`)으로 구성 |

**FIFO 제어(`control_unit`)** — `{push, pop}` 조합별로 포인터를 갱신합니다.

| `{push, pop}` | 동작 |
| :---: | :--- |
| `10` | `full`이 아니면 `wptr` 증가, `empty` 해제, 다음 `wptr`가 `rptr`와 같아지면 `full` |
| `01` | `empty`가 아니면 `rptr` 증가, `full` 해제, 다음 `rptr`가 `wptr`와 같아지면 `empty` |
| `11` | `full`이면 read만, `empty`이면 write만, 그 외에는 `wptr` / `rptr` 둘 다 증가 |

**`uart_top` 연결**

| 인스턴스 | 핵심 연결 |
| :--- | :--- |
| `U_FIFO_RX` | `push = w_rx_done`, `push_data = w_rx_data`, `pop = ~w_tx_fifo_full` |
| `U_FIFO_TX` | `push = ~w_rx_fifo_empty`, `push_data = w_rx_fifo_pop_data`, `pop = ~w_tx_busy` |
| `U_UART_TX` | `tx_start = ~w_tx_fifo_empty`, `tx_data = w_tx_fifo_pop_data` |

> `register_file`은 리셋이 없는 메모리라 첫 write 전에는 `pop_data`가 `XX`로 보이는 것이 정상입니다.

---

## 🎯 Verification Scenario

| Label | 검증 내용 | 입력 생성 (Stimulus) | 확인 방법 (Check) |
| :---: | :--- | :--- | :--- |
| **UART_1** | **단일 데이터 정상 동작** — 정해진 8비트 데이터(예: `8'hA5`) 1개를 `uart_rx`로 입력했을 때 FIFO를 거쳐 `uart_tx`로 온전히 출력되는지 확인 | Generator에서 고정된 8비트 데이터를 생성해 Driver로 전달, 기본 Baudrate 타이밍 사용 | Scoreboard에서 입력(Expected)과 출력값을 비교해 PASS / FAIL 출력 |
| **UART_2** | **랜덤 데이터 연속 입력 및 Full 확인** — `randomize()`로 10개 이상의 랜덤 데이터를 연속 입력해 정상 처리되는지 확인하고, 출구를 막아 FIFO full이 뜨는지 확인 | Generator에서 10개 이상의 트랜잭션을 랜덤 값으로 생성, 테스트벤치 최상단에서 `force dut.w_tx_busy = 1'b1;`로 TX 출력을 강제로 막음 | 파형에서 데이터 누적 시 `w_tx_fifo_full`이 1이 되는지 확인 |
| **UART_3** | **제어 신호 무결성 (Assertion)** — 시뮬레이션 동안 reset이 초기에 정상 인가되는지, `b_tick`이 멈추지 않고 주기적으로 발생하는지 확인 | 전체 시뮬레이션 동작 (단일 입력 및 랜덤 입력 시나리오 모두 포함) | SVA를 추가해 reset과 `b_tick` 조건이 어긋나면 즉시 Error를 출력하도록 자동 감시 |

---

## 🧩 Testbench Code

Generator → Driver → DUT → Monitor → Scoreboard 구조이며, 클래스 간 데이터는 `mailbox`로, 트랜잭션 단위 동기화는 `event`로 주고받습니다.

| 클래스 | 역할 |
| :--- | :--- |
| **Generator** | 트랜잭션 생성. `gen2drv_mbox`로 Driver에, `gen2scb_mbox`로 Scoreboard에(기대값) 전달하고 `gen_next_ev`를 기다림 |
| **Driver** | 트랜잭션의 `tx_data`를 UART 프로토콜(Start → D0~D7 → Stop)에 맞춰 `uart_rx`에 1비트당 `baud_tick` 클럭씩 인가 |
| **Monitor** | `uart_tx`의 Start bit를 기다린 뒤 비트 중앙을 샘플링해 `rx_data`를 복원하고 `mon2scb_mbox`로 전달 |
| **Scoreboard** | Generator의 기대값을 queue에 저장하고, Monitor 값이 들어오면 `pop_front` 후 비교해 PASS / FAIL 출력 (queue가 비어 있으면 ERROR) |

### 1. 단일 데이터 (UART_1)

랜덤이 아닌 고정값(`8'hA5`)을 넣고 같은 값이 나오는지 검증합니다. 입력과 출력을 비교하기 위해 `gen2scb_mbox`를 추가했습니다.

<p align="center">
  <img src="docs/generator_fixed.png" alt="Generator with fixed data 8'hA5" width="45%">
</p>

**Driver** — UART 프로토콜에 맞춰 `baud_tick`만큼 기다리며 LSB부터 1비트씩 전송

<p align="center">
  <img src="docs/driver_class.png" alt="Driver class" width="45%">
  <img src="docs/driver_run.png" alt="Driver run task" width="38%">
</p>

**Monitor** — Start bit 인식 후 `baud_tick / 2`만큼 기다려 비트 중간 값을 읽음

<p align="center">
  <img src="docs/monitor_class.png" alt="Monitor class" width="45%">
  <img src="docs/monitor_run.png" alt="Monitor run task" width="45%">
</p>

LSB first 전송을 위해 Driver와 Monitor 모두 `data[i]`의 `i = 0 → 7` 순서로 처리합니다.

<p align="center">
  <img src="docs/driver_lsb_first.png" alt="Driver LSB first" width="45%">
  <img src="docs/monitor_lsb_first.png" alt="Monitor LSB first" width="45%">
</p>

**Scoreboard** — Generator에서 받은 값을 queue에 저장하고, Monitor 값이 들어오면 꺼내 비교

<p align="center">
  <img src="docs/scoreboard_class.png" alt="Scoreboard class" width="45%">
  <img src="docs/scoreboard_run.png" alt="Scoreboard run task" width="45%">
</p>

### 2. 랜덤 데이터 (UART_2)

Generator에서 `tr.randomize()`로 매번 다른 `tx_data`를 생성합니다.

<p align="center">
  <img src="docs/generator_random.png" alt="Generator with randomize" width="45%">
</p>

### 3. Full 확인 (UART_2-1)

테스트벤치에서 `force dut.w_tx_busy = 1'b1;`로 TX 출력을 막아 결과값을 하나만 저장하도록 고정합니다.

<p align="center">
  <img src="docs/tb_force_busy.png" alt="Testbench forcing w_tx_busy" width="35%">
</p>

### 4. Assertion — reset, b_tick (UART_3)

```systemverilog
// reset 이후 rx_data 가 0 이어야 한다
property Preset_check;
    @(posedge clk) reset |=> (rx_data == 0);
endproperty
reg_reset_check :
assert property (Preset_check)
else $display("%t : Assert error : reset check", $time);

// reset 이 아닐 때 b_tick 이 발생하면 1비트 시간(10416 클럭) 뒤에도 b_tick 이 다시 발생해야 한다
property B_TICK_check;
    @(posedge clk) disable iff (reset) b_tick |-> ##(10416) b_tick;
endproperty
reg_b_tick_check :
assert property (B_TICK_check)
else $display("%t : Assert error : b_tick check", $time);
```

Assertion이 실제로 동작하는지 확인하기 위해 테스트벤치에서 **신호를 강제로 고정**합니다.

| 대상 | 강제 방법 |
| :--- | :--- |
| reset check | `force uf_if.rx_data = 8'hFF;` |
| b_tick check | `#10000; force dut.w_b_tick = 1'b1; #10; release dut.w_b_tick;` |

<p align="center">
  <img src="docs/tb_force_rxdata.png" alt="Testbench forcing rx_data" width="35%">
  <img src="docs/tb_force_btick.png" alt="Testbench forcing b_tick" width="25%">
</p>
<p align="center">
  <img src="docs/sva_reset_code.png" alt="SVA reset check" width="48%">
  <img src="docs/sva_btick_code.png" alt="SVA b_tick check" width="48%">
</p>

---

## 🖥️ Simulation

### 1. 단일 데이터 (UART_1) — `8'hA5` 

입력 `A5 (1010_0101)`이 LSB부터 1비트씩 들어오며 수신 데이터가 `80 → 40 → A0 → 50 → 28 → 94 → 4A → A5` 순으로 채워진 뒤 FIFO를 거쳐 `uart_tx`로 출력됩니다. 반복 입력 모두 Scoreboard에서 **PASS** (`GEN_DATA : a5, MON_DATA : a5`)입니다.

<p align="center">
  <img src="docs/sim_single_wave.png" alt="Single data simulation waveform" width="90%">
</p>
<p align="center">
  <img src="docs/sim_single_wave_zoom.png" alt="Single data simulation waveform (zoom)" width="90%">
</p>
<p align="center">
  <img src="docs/sim_single_log.png" alt="Single data Tcl console" width="45%">
</p>

### 2. 랜덤 데이터 (UART_2)

랜덤 값 `BD → 30 → FE → D3 → 82` 등이 연속 입력되며 모두 **PASS**입니다. 예를 들어 `0x30`은 `0011_0000`이므로 선로에는 `0000_1100` 순서(LSB first)로 나갑니다.

<p align="center">
  <img src="docs/sim_random_wave_1.png" alt="Random data simulation waveform 1" width="90%">
</p>
<p align="center">
  <img src="docs/sim_random_wave_2.png" alt="Random data simulation waveform 2" width="90%">
</p>
<p align="center">
  <img src="docs/sim_random_wave_3.png" alt="Random data simulation waveform 3" width="90%">
</p>
<p align="center">
  <img src="docs/sim_random_wave_4.png" alt="Random data simulation waveform 4" width="90%">
</p>
<p align="center">
  <img src="docs/sim_random_log.png" alt="Random data Tcl console" width="55%">
</p>

### 2-1. Full 확인

`w_tx_busy`를 강제로 1로 고정하면 10개의 랜덤 데이터 중 **첫 번째 값(`BD`)만 저장**되고 `w_tx_fifo_full`이 1로 올라갑니다. 이후 입력은 기대값과 달리 모니터에서 계속 첫 값(`bd`)만 관측되어 Scoreboard에서 첫 값 이후 **FAIL**이 출력되며, 출구를 막은 상황에서 나오는 의도한 결과입니다.

<p align="center">
  <img src="docs/sim_full_wave.png" alt="FIFO full simulation waveform" width="90%">
</p>
<p align="center">
  <img src="docs/sim_full_log.png" alt="FIFO full Tcl console (FAIL after first value)" width="55%">
</p>

### 3. Assertion (UART_3)

* **reset check**: `rx_data`를 `8'hFF`로 강제하면 reset 직후(15 ns) `Assert error : reset check`가 출력됩니다.
* **b_tick check**: `b_tick`을 강제로 고정했다 해제하면 `Assert error : b_tick check`가 출력됩니다.

<p align="center">
  <img src="docs/sim_sva_reset_wave.png" alt="Reset check waveform" width="90%">
</p>
<p align="center">
  <img src="docs/sim_sva_reset_log.png" alt="Reset check Tcl console" width="55%">
</p>
<p align="center">
  <img src="docs/sim_sva_btick_log.png" alt="b_tick check Tcl console" width="55%">
</p>

---

## 🔧 Troubleshooting

| # | 문제 현상 (Issue) | 원인 및 해결 |
| --- | --- | --- |
| **1** | **Loopback 데이터가 테스트벤치에서 정상 관측되지 않음** — 파형에서 `rx_data`와 FIFO `pop_data`가 `XX`로 남고, 로그에서 `output = 00x`, `rx_done = x`가 출력되며 여러 입력값(`0xA5`, `0xF3`, `0x33`)이 같은 시각에 겹쳐 찍힘 | **원인**: UART 비트 타이밍과 FIFO / `tx_busy` handshake 시점이 맞지 않아, 수신 완료(`rx_done`)·FIFO push/pop·송신 시작 시점이 어긋난 것으로 판단 <br><br> **해결**: <br> ① **TB** — Driver와 Monitor를 UART 프로토콜에 맞춰 `baud_tick`(1비트 = 10416클럭) 단위로 동작시키고, Monitor는 Start bit 인식 후 `baud_tick / 2`를 기다려 **비트 중앙을 샘플링** <br> ② **UART** — `uart_rx`는 Start bit 이후 8 tick으로 중앙을 맞추고 16 tick마다 샘플링, `uart_tx`는 비트당 16 tick으로 송출 <br> ③ **FIFO** — `{push, pop}` 동시 발생 시 `full`이면 read만, `empty`이면 write만 증가하도록 포인터 갱신 <br> ④ **연결** — `tx_start = ~tx_fifo_empty`, `FIFO_TX.pop = ~tx_busy`, `FIFO_RX.pop = ~tx_fifo_full`로 FIFO 상태와 `tx_busy`로 흐름 제어 |

<details>
<summary><b>Troubleshooting 당시 파형 및 로그</b></summary>

<p align="center">
  <img src="docs/trouble_wave.png" alt="Troubleshooting waveform" width="90%">
</p>
<p align="center">
  <img src="docs/trouble_log.png" alt="Troubleshooting log" width="55%">
</p>

</details>

---

## 👨‍💻 Author

- **GitHub**: [@ethan000106](https://github.com/ethan000106)
