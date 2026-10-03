#!/usr/bin/env python3
"""Make simulation copies of the core's Verilog that Icarus Verilog accepts.

Quartus accepts a net or register used above its declaration; Icarus 13 does not.
This hoists every module-level `wire`/`reg` declaration to the top of its module
(`wire x = expr;` becomes a hoisted `wire x;` and an in-place `assign x = expr;`)
and rewrites rocket.sv's array-initialised net. Logic is not changed.

usage: prep_for_icarus.py OUTDIR FILE...
"""
import pathlib, re, sys

def rocket_table(src):
    m = re.search(r"wire \[7:0\] header_xor\[52\] = '\{(.*?)\};", src, re.S)
    if not m:
        return src
    vals = [v.strip() for v in m.group(1).replace('\n', ' ').split(',')]
    assert len(vals) == 52
    init = 'reg [7:0] header_xor[0:51];\ninitial begin\n' + ''.join(
        f"\theader_xor[{i}] = 8{v};\n" for i, v in enumerate(vals)) + 'end'
    return src[:m.start()] + init + src[m.end():]

DECL = re.compile(r'^(wire|reg)\b[^;]*;', re.M | re.S)
ASSIGNED = re.compile(r'^wire\s*((?:signed\s*)?(?:\[[^\]]+\])?)\s*(\w+)\s*=\s*(.*);$', re.S)

def hoist(module):
    head_end = module.index(');') + 2
    head, body = module[:head_end], module[head_end:]
    hoisted = []
    def repl(m):
        text = m.group(0)
        a = ASSIGNED.match(text)
        if a:
            hoisted.append(f'wire {a.group(1)} {a.group(2)};')
            return f'assign {a.group(2)} = {a.group(3)};'
        assert text.startswith('reg') or '=' not in text, text
        hoisted.append(text)
        return ''
    body = DECL.sub(repl, body)
    return head + '\n' + '\n'.join(hoisted) + '\n' + body

out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for name in sys.argv[2:]:
    src = rocket_table(pathlib.Path(name).read_text())
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)  # commented-out declarations
    parts = re.split(r'(?m)^(?=module\b)', src)
    done = ''.join(hoist(p) if p.startswith('module') else p for p in parts)
    (out / pathlib.Path(name).name).write_text(done)
