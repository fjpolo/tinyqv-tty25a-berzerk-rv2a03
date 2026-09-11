import sys

state = {'W': '0', 'Y': '0', '[': '0', '^': '0', ']': '0'}
target_start = 20500000000  # 20.5ms
target_end   = 23500000000  # 23.5ms
printed = 0
current_time = 0

with open('tb_qspi.vcd', 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        if line.startswith('#'):
            current_time = int(line[1:])
            if current_time > target_end:
                break
        elif current_time >= target_start:
            for sig in state.keys():
                if line.endswith(' ' + sig):
                    val = line.split()[0]
                    state[sig] = val
                    if printed < 40:
                        print(f"Time {current_time/1e9:.4f} ms: {sig}={val} | Tri={state['W']} Sq2={state['Y']} Sq1={state['[']} Noi={state['^']} Mix={state[']']}")
                        printed += 1
