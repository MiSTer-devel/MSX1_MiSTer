"""openMSX trace of vdpcmd (trace.tcl) -> data file for rtl/peripheral/VIDEO/VDP/tb/vdp_vdpcmd_tb.sv.
usage: mkdata.py <trace> <VDP cycles per frame: 358416 NTSC, 428184 PAL> <output>
Line 1: 'R' and R#0..R#23 before the first test (hex).
Then per test: cmd start abort00 abort cpu_first cpu_n cpu_gap
(VDP cycles: start, cpu_first after the IRQ before the command; abort00 / abort after the
next IRQ: the data byte 00 and the 0xAE that writes R#46)."""
import sys
src, FT, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
ev = [l.split() for l in open(src) if l.strip()]
regs = [0] * 48
latch = None
tests, cur, last_irq = [], None, None
fills = 0
started = False
for p in ev:
    t = int(p[1]) * FT + int(p[2])
    if p[0] == 'I':
        last_irq = t
    elif p[0] == 'P':
        v = int(p[3], 16)
        if latch is None:
            latch = (v, t); continue
        if v & 0xC0 == 0x80:
            r = v & 0x3F
            if not started: regs[r] = latch[0]
            if r == 46 and latch[0] == 0 and cur is not None and 'abort' not in cur:
                cur['abort'] = t - last_irq; cur['abort00'] = latch[1] - last_irq
        latch = None
    elif p[0] == 'B':
        r, v = int(p[3]) - 1, p[4]      # the callback sees R#17 after its increment
        if r != 46:
            if not started: regs[r] = int(v, 16)
            continue
        if not started and v == 'C0' and fills < 2:
            fills += 1; continue        # the two initial page fills
        if cur is None and v in ('D0', '9B', 'E0', '8A', 'C0'):
            started = True
            cur = {'cmd': v, 'start': t - last_irq, 'irq': last_irq, 'cpu': []}
        elif cur is not None and v == 'C0':
            tests.append(cur); cur = None   # cleanup fill after LMCM
    elif p[0] == 'D' and cur is not None and 'abort' not in cur:
        cur['cpu'].append(t - cur['irq'])
with open(out, 'w') as f:
    f.write('R ' + ' '.join(f'{x:02X}' for x in regs[:24]) + '\n')
    for c in tests:
        cpu = c['cpu']
        gap = (cpu[1] - cpu[0]) if len(cpu) > 1 else 0
        assert all(b - a == gap for a, b in zip(cpu, cpu[1:]))
        f.write(f"{int(c['cmd'],16)} {c['start']} {c['abort00']} {c['abort']} {cpu[0] if cpu else 0} {len(cpu)} {gap}\n")
print(len(tests), 'tests ->', out)
