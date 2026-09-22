#!/usr/bin/env python3
"""Build debug/release with default/no optimizations and check both reset policies."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', default=os.environ.get('LIVT_GHDL_PATH', 'ghdl'))
    args = parser.parse_args()
    environment = dict(os.environ)
    environment.pop('_JAVA_OPTIONS', None)
    stage = Path(tempfile.mkdtemp(prefix='livt-net-ethernet-matrix-'))
    print(f'Matrix evidence: {stage}', flush=True)

    def run(command, name):
        log = stage / (name + '.log')
        with log.open('w') as output:
            result = subprocess.run(command, cwd=ROOT, env=environment, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=600)
        if result.returncode:
            raise RuntimeError(f'{name} failed ({result.returncode}): {log}')

    for profile in ('debug', 'release'):
        for optimization in ('default', 'none'):
            name = f'{profile}-{optimization}'
            build = ['livt', 'build', '-f']
            if profile == 'release':
                build.append('-R')
            if optimization == 'none':
                build += ['-O', 'none']
            print(f'Building {name}', flush=True)
            run(build, name + '-build')
            for reset in ('sync', 'async'):
                case = name + '-' + reset
                run([sys.executable, str(HERE / 'run.py'), '--generated',
                     str(ROOT / 'out' / profile), '--ghdl', args.ghdl,
                     '--reset-style', reset], case)
                print(f'PASS {case}', flush=True)
    print(f'All 8 Ethernet configurations passed; evidence: {stage}')


if __name__ == '__main__':
    main()
