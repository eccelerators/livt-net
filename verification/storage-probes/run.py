#!/usr/bin/env python3
"""Prepare or run equal-operation packet-storage synthesis comparisons."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path, help="new directory for probe sources, HDL and reports")
parser.add_argument("--prepare-only", action="store_true")
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
here = Path(__file__).resolve().parent
source = here.parents[1] / "src"
env = os.environ.copy()
env.pop("_JAVA_OPTIONS", None)
livt = env.get("LIVT", "livt")
vivado = env.get("LIVT_VIVADO_PATH", "vivado")
for name in ("array", "ram", "header-array", "header-ram"):
    project = output / name
    (project / "src").mkdir(parents=True)
    header = name.startswith("header-")
    files = ["IPacketData", "RamPacketData"]
    files += ["PacketHeader", "PacketParseResult", "NetworkOrder"] if header else ["ArrayPacketData"]
    for stem in files:
        matches = list(source.rglob(stem + ".lvt"))
        if len(matches) != 1:
            raise RuntimeError(f"Expected one source for {stem}: {matches}")
        shutil.copy2(matches[0], project / "src" / matches[0].name)
    template = "header-array" if header else "array"
    text = (here / (template + ".lvt.template")).read_text()
    if name == "ram":
        text = text.replace("ArrayPacketData<128>", "RamPacketData<128>")
    (project / "src/PacketStorageProbe.lvt").write_text(text)
    if name == "header-ram":
        path = project / "src/PacketHeader.lvt"
        text = path.read_text().replace("namespace Livt.Net", "namespace Livt.Net\nusing Livt.IO", 1)
        text = text.replace("header: byte[SIZE]", "header: Ram<byte, SIZE>")
        text = text.replace("this.source = source", "this.source = source\n\t\tthis.header = new Ram<byte, SIZE>()", 1)
        text = text.replace("header[i] = value", "header.Write(i, value)")
        text = text.replace("return header[index]", "return header.Read(index)")
        path.write_text(text)
    shutil.copy2(here / "livt.toml.template", project / "livt.toml")
    if args.prepare_only:
        continue
    with (project / "build.log").open("w") as log:
        for command in ([livt, "sync", "-f"], [livt, "vendor", "vivado-ip", "-R"],
                        [vivado, "-mode", "batch", "-source", str(here / "synth.tcl"),
                         "-nojournal", "-log", str(project / "synthesis.log")]):
            subprocess.run(command, cwd=project, env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
    print(f"{name}: {project / 'utilization.rpt'}")
