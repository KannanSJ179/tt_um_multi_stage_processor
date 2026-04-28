## How it works

`tt_um_multi_stage_processor` is a mixed-signal processing pipeline that combines four datapath units:
- 16-bit free-running counter
- 16-bit maximal-length LFSR
- 16-bit LFSR-fed shift register
- 8-bit analog sampler

These feed a configurable 5-stage combinational pipeline:

1. **Source Selection**  
   Controlled by `mode_sel` (`ui_in[2:0]`), selecting from multiple internal data sources.

2. **ALU Stage**  
   A 3-bit FSM cycles through operations:
   - ADD, SUB
   - XOR, AND
   - OR with constant
   - Counter/LFSR-based arithmetic
   - Pass-through  
   The `config` input (`uio_in[3:0]`) acts as the operand.

3. **Shift Stage**  
   A fixed-width shift (0–7 bits) based on `config[2:0]`.

4. **Analog Injection**  
   The shifted value is XORed with `analog_sample`, which comes from sampling `ua[0]`.  
   The analog signal originates from `ua[1]` via the `yen_top` analog block.

5. **Output Register**  
   Final output is registered and driven on `uo_out[7:0]`.

**Test Mode:**  
If `ui_in[7] = 1`, output is forced to the counter value for deterministic testing.

**Debug:**  
`ui_in[6:4]` selects internal signals that appear on `uio_out`.

---

## How to test

1. Apply reset: set `rst_n = 0` for a few clock cycles, then release.
2. Enable the design: set `ena = 1`.

### Test mode verification
- Set `ui_in = 8'b1000_0000`
- Observe `uo_out` counting up → confirms base functionality

### Normal operation
- Set `mode_sel` using `ui_in[2:0]`
- Provide configuration via `uio_in[3:0]`
- Observe processed output on `uo_out`

### Debug verification
- Set `ui_in[6:4]` from 0–7
- Observe internal signals on `uio_out`

### FSM control
- Set `ui_in[3] = 1` → FSM holds state
- Clear it → normal operation resumes

### Analog verification
- Apply signal to `ua[1]`
- Set debug to show analog sample (`ui_in[6:4] = 3'b101`)
- Observe influence on output over time

---

## External hardware

Optional:
- Function generator or DAC connected to `ua[1]` (0–VDD range)

If no analog source is used, the digital logic still functions normally.
