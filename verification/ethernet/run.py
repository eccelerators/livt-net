#!/usr/bin/env python3
"""Verify the generated EthernetFrameIo at native AXI clock edges."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generated', type=Path, default=ROOT / 'out/debug')
    parser.add_argument('--ghdl', default=os.environ.get('LIVT_GHDL_PATH', 'ghdl'))
    parser.add_argument('--reset-style', choices=('sync', 'async'),
                        help='Override the DUT reset-policy generic; omit to use the generated default')
    args = parser.parse_args()
    generated = args.generated.resolve()
    # The default specialization is also exercised by the ordinary library tests.
    candidates = [p for p in generated.rglob('Livt.Net.EthernetFrameIo*.vhd')
                  if not p.name.endswith('.Package.vhd') and
                  ('_g_' not in p.name or '_g_128_2048_2048_' in p.name)]
    if len(candidates) != 1:
        raise RuntimeError(f'Expected one default FrameIo specialization: {candidates}')
    source = candidates[0].read_text()
    entity = re.search(r'^entity (\w+) is', source, re.M)[1]
    package = candidates[0].with_suffix('.Package.vhd').read_text()
    package_name = re.search(r'^package (\w+) is', package, re.M)[1]
    records = dict(re.findall(r'type (\w+) is\s+record(.*?)end record;', package, re.S))
    ports = re.findall(r'^\s*(\w+) : (in|out) (t_\w+);?', source.split('end;')[0], re.M)
    declarations, mappings, procedures = [], [], []
    for name, direction, typ in ports:
        if name.startswith('ctor_'):
            continue
        fields = re.findall(r'(\w+)\s*:\s*([^;]+);', records[typ])
        initial = ''
        if direction == 'in':
            zero = lambda t: "'0'" if t == 'std_logic' else ('false' if t == 'boolean' else "(others => '0')")
            initial = ' := (' + ', '.join(f'{n} => {zero(t)}' for n, t in fields) + ')'
        declarations.append(f'signal {name} : {typ}{initial};')
        mappings.append(f'{name} => {name}')
        if direction != 'in':
            continue
        method = name[:-3]
        output_fields = re.findall(r'(\w+)\s*:\s*([^;]+);', records[typ[:-2] + 'out'])
        result_type = next((t for n, t in output_fields if n == 'return_value'), None)
        params, assignments = [], []
        for n, t in fields:
            if n == 'run':
                continue
            arg_type = 'integer' if t.startswith('signed') else t
            params.append(f'arg_{n}: {arg_type}')
            value = f'to_signed(arg_{n}, 32)' if t.startswith('signed') else f'arg_{n}'
            assignments.append(f'{name}.{n} <= {value};')
        if result_type:
            params.append('expected: ' + ('integer' if result_type.startswith('signed') else result_type))
        signature = '(' + '; '.join(params) + ')' if params else ''
        assertion = ''
        if result_type:
            value = 'to_signed(expected, 32)' if result_type.startswith('signed') else 'expected'
            assertion = f'assert {method}_out.return_value = {value} report "{method}: unexpected result" severity failure;'
        procedures.append(f'''procedure call_{method}{signature} is
          variable cycles: natural := 0;
        begin
          wait until falling_edge(clk);
          {' '.join(assignments)}
          {name}.run <= '1'; tick;
          wait until falling_edge(clk); {name}.run <= '0';
          loop
            tick; cycles := cycles + 1;
            exit when {method}_out.busy = '1';
            assert cycles < 20 report "{method}: no acceptance" severity failure;
          end loop;
          while {method}_out.busy = '1' loop
            tick; cycles := cycles + 1;
            assert cycles < 1000 report "{method}: no completion" severity failure;
          end loop;
          {assertion}
        end;''')
    bench = (HERE / 'transfers.vhd').read_text()
    for key, value in {'ENTITY': entity, 'PACKAGE': package_name,
                       'DECLARATIONS': '\n'.join(declarations),
                       'MAPPINGS': ',\n'.join(mappings),
                       'PROCEDURES': '\n'.join(procedures),
                       'RESET_GENERIC': ('' if args.reset_style is None else
                           'generic map (LVT_RESET_ASYNC => ' +
                           ('true' if args.reset_style == 'async' else 'false') + ')')}.items():
        bench = bench.replace('@' + key + '@', value)
    stage = Path(tempfile.mkdtemp(prefix='livt-net-ethernet-'))
    (stage / 'transfers.vhd').write_text(bench)
    print(f'Evidence: {stage}', flush=True)
    commands = [
        [args.ghdl, '-i', '--std=08', *map(str, generated.rglob('*.vhd')), str(stage / 'transfers.vhd')],
        [args.ghdl, '-m', '--std=08', 'frame_transfers'],
        [args.ghdl, '-r', '--std=08', 'frame_transfers', '--assert-level=error'],
    ]
    for i, command in enumerate(commands):
        result = subprocess.run(command, cwd=stage, capture_output=True, text=True, timeout=180)
        (stage / f'{i}.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'Command failed: {stage / str(i)}.log\n{result.stdout[-3000:]}{result.stderr[-3000:]}')
    if 'Simulation finished: Ethernet transfers' not in result.stdout:
        raise RuntimeError(f'Missing completion marker: {stage}')
    print(result.stdout)


if __name__ == '__main__':
    main()
