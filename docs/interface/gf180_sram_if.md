# GF180 SRAM implementation interface

> Optional INT8 storage implementation; the default register-backed accelerator
> remains unchanged.

- **Modules:** `gf180_sram_controller`, `matrix_buffer_ab_sram`,
  `matrix_buffer_c_sram`
- **Owner:** shared

## Overview

`accelerator_top` and `subsystem_12` gain `USE_GF180_SRAM=0` and explicit
`VDD`/`VSS` inout supply ports. With the parameter zero, existing register
buffers and zero-wait behavior are selected; unconnected supplies are unused.
With it one, the supported build is INT8, ACC_W=APB_DW=32, and physical
dimensions 1..16. Software register addresses and numerical results do not
change, but APB masters must honor `PREADY`.

## Block diagram

```text
50 MHz APB / array -> byte requests -> divided-clock controller -> GF180 SRAM
                     vector / row staging and ready/valid backpressure
```

## Parameters

The byte controller has `NUM_MACROS` (positive power of two) and
`ADDR_W=9+$clog2(NUM_MACROS)`. Each macro is the actual
`gf180mcu_fd_ip_sram__sram512x8m8wm1`, not synthesized simulation RTL.
The divided memory clock is system clock / 4: 12.5 MHz with a 50 MHz input.

## Ports

| Controller port | Meaning |
| --- | --- |
| `clk`, `rst_n` | System clock and active-low reset; reset cancels protocol state, not SRAM contents |
| `req_valid`, `req_ready` | One byte request accepted on a system rising edge |
| `req_write`, `req_addr`, `req_wdata`, `req_wmask` | Byte operation; mask bits one mean write that bit |
| `rsp_valid`, `rsp_ready`, `rsp_rdata` | One ordered response per request, including writes; held until accepted |
| `sram_clk` | Actual divided clock, to be declared as a generated clock |
| `VDD`, `VSS` | Explicit macro supply connections |

Requests remain stable while stalled. Responses remain stable under
backpressure. There is only one outstanding request. Address widths cover
exactly the declared power-of-two macro array.

## Register map

The A/B and C APB maps, bank bits and compact row-major packing match the
existing [A/B](matrix_buffer_a_b_if.md) and [C](matrix_buffer_c_if.md) contracts.
A/B data writes and C data reads may insert wait states; pointers advance
exactly once at APB completion. Partial final packed A/B words ignore unused
lanes. Overflow completes with `PSLVERR` and does not write SRAM.

Control accesses retain the existing selected-bank semantics: a combined
bank-select/pointer-reset write resets the previously APB-selected bank.
C control writes wait for in-flight storage operations to complete.
Software must not overwrite an active tile or change its dimensions.

## Behavior

- A/B use two 512-byte macros, one per software bank: bytes 0..255 store A,
  bytes 256..511 store B. At start, bank and dimensions are captured. Each
  vector is gathered serially and held stable until the array accepts it.
  APB writes can interleave with gathering the other bank.
- C uses four macros: each software bank holds 1024 bytes. One accepted row
  is staged and serialized; `c_in_ready` backpressures the array until that
  row commits. APB read responses assemble four bytes, least-significant
  byte first. A read of an as-yet-uncommitted row waits.
- In SRAM mode, completion/IRQ is delayed until the last accepted C row
  has actually committed to SRAM, not just entered the staging register.
- Macro pins change only during the low-clock preparation phase. `CEN` is
  initially high; `GWEN` and `WEN` use the actual active-low macro polarity.
  Responses are sampled 60 ns after the macro clock edge at 50 MHz system
  frequency, allowing the official model's output delay.
- Reset finishes an existing memory high pulse before holding its clock low.
  It discards pending responses and restores pointer/bank state. An interrupted
  write may have modified SRAM; software must reload a tile after reset.

## Notes

Six macro bodies occupy 1.2564016608 mm^2, before halos/PG/logic, within a
2.0736 mm^2 core budget only as a macro-area lower bound. Logic utilization,
placement, power and routing still require real GF180 implementation.
The internal slow-clock architecture is explicit and still needs course
acceptance and full generated-clock STA. It is not a 50 MHz SRAM claim.
