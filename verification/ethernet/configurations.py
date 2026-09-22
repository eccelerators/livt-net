#!/usr/bin/env python3
"""Check invalid Net specializations without mutating the package or its pins."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    stage = Path(tempfile.mkdtemp(prefix='livt-net-invalid-'))
    (stage / 'src').mkdir()
    (stage / 'livt.toml').write_text('[project]\nname="NetConfiguration"\npath="src"\noutdir="out"\n')
    cases = ['EthernetFrameParser<13>', 'ArpPacketParser<41>',
             'Ipv4PacketParser<33>', 'TcpHeaderParser<53>', 'IcmpEchoResponder<41>',
             'EthernetFrameIo<0>', 'EthernetFrameIo<127>', 'EthernetFrameIo<2040>',
             'EthernetFrameIo<128, 64>', 'EthernetFrameIo<128, 2049>',
             'EthernetFrameIo<128, 2048, 0>', 'EthernetFrameIo<128, 2048, 2049>']
    environment = dict(os.environ)
    environment.pop('_JAVA_OPTIONS', None)
    failures = []
    print(f'Evidence: {stage}', flush=True)
    for i, specialization in enumerate(cases):
        shutil.rmtree(stage / 'src')
        (stage / 'src').mkdir()
        name = specialization.split('<')[0]
        names = [name, 'Axi4LiteEthernetLiteAdapter', 'IAxi4LiteEthernetLiteMaster']
        if name == 'IcmpEchoResponder':
            names += ['EthernetFrameBuilder', 'Ipv4PacketParser', 'Ipv4HeaderChecksum']
        for component in names:
            shutil.copy2(ROOT / 'src' / (component + '.lvt'), stage / 'src')
        if name == 'EthernetFrameIo':
            shutil.copytree(ROOT / '.livt/deps/Livt.IO-1.2.0-dev/src/memory', stage / 'src/memory')
        args = 'this.axi, mac' if specialization.startswith('EthernetFrameIo') else ''
        (stage / 'src/InvalidConfiguration.lvt').write_text(f'''namespace Livt.Net.Verification
using Livt.Net
component InvalidConfiguration {{
 axi: Axi4LiteEthernetLiteAdapter
 subject: {specialization}
 new() {{
  var mac: byte[6] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  this.axi = new Axi4LiteEthernetLiteAdapter()
  this.subject = new {specialization}({args})
 }}
}}
''')
        for action in ('validate', 'build'):
            result = subprocess.run([environment.get('LIVT', 'livt'), action, '--json'],
                                    cwd=stage, env=environment, capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            log = f'case-{i}-{action}.log'
            (stage / log).write_text(output)
            objects = []
            for line in result.stdout.splitlines():
                try:
                    obj = json.loads(line)
                    if obj.get('command') == action:
                        objects.append(obj)
                except (json.JSONDecodeError, AttributeError):
                    pass
            diagnostics = [d for obj in objects for d in obj.get('diagnostics', [])]
            rejected = (result.returncode != 0 and len(objects) == 1 and objects[0].get('success') is False
                        and any(d.get('code', '').endswith('failedStaticAssert') and d.get('file')
                                for d in diagnostics)
                        and not any(word in output for word in ('NullPointerException', 'Error executing EValidator')))
            if rejected:
                print(f'Rejected {specialization}: {action}', flush=True)
            else:
                reason = 'invalid configuration accepted' if result.returncode == 0 else 'unrelated compiler failure'
                failures.append({'specialization': specialization, 'command': action, 'reason': reason, 'log': log})
                print(f'FAIL {specialization}: {action}: {reason}', flush=True)
    (stage / 'summary.json').write_text(json.dumps({'total': len(cases), 'commands': 2 * len(cases), 'failures': failures}, indent=2))
    if failures:
        raise RuntimeError(f'{len(failures)} configuration checks failed; evidence: {stage}')
    print(f'All {len(cases)} invalid configurations rejected by validate and build; evidence: {stage}')



if __name__ == '__main__':
    main()
