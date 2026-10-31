#!/usr/bin/env python3
"""Genera `public/build.h` para compilar Xash3D-FWGS desde un checkout sin CI.

El motor incluye `build.h` en practicamente todos sus headers, pero ese archivo
no esta versionado: en el repositorio oficial lo produce el propio waf en las
builds de integracion continua. Al compilar a mano hace falta crearlo con los
macros de plataforma (arquitectura, endianness, sistema operativo) o el build
falla con `#error` en 3rdparty/library_suffix/include/buildenums.h.
"""

from __future__ import annotations

import argparse
import platform
import struct
import subprocess
import sys
from pathlib import Path

# Xash3D usa nombres propios: XASH_X86 = 32 bits, XASH_AMD64 = x86_64.
ARCH = {
    "x86_64": "XASH_AMD64",
    "amd64": "XASH_AMD64",
    "i386": "XASH_X86",
    "i686": "XASH_X86",
    "x86": "XASH_X86",
    "aarch64": "XASH_ARM",
    "arm64": "XASH_ARM",
    "armv7l": "XASH_ARM",
    "armv6l": "XASH_ARM",
    "riscv64": "XASH_RISCV",
    "ppc64le": "XASH_PPC",
    "mips": "XASH_MIPS",
}
OS_MACRO = {
    "Linux": ("XASH_LINUX", "XASH_POSIX"),
    "Darwin": ("XASH_APPLE", "XASH_POSIX"),
    "Windows": ("XASH_WIN32", None),
    "FreeBSD": ("XASH_FREEBSD", "XASH_POSIX"),
}


def git(path: Path, *args: str) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(path), *args],
            capture_output=True, text=True, check=True, timeout=15,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("engine_dir", nargs="?",
                    default=".src/xash3d-fwgs", help="checkout de xash3d-fwgs")
    ap.add_argument("--force", action="store_true", help="sobrescribe build.h")
    args = ap.parse_args()

    engine = Path(args.engine_dir).resolve()
    if not (engine / "wscript").is_file():
        print(f"error: {engine} no parece xash3d-fwgs (falta wscript)", file=sys.stderr)
        return 1

    out = engine / "public" / "build.h"
    if out.is_file() and not args.force:
        print(f"build.h ya existe en {out} (usa --force para regenerarlo)")
        return 0

    machine = platform.machine().lower()
    arch = ARCH.get(machine)
    if not arch:
        print(f"error: arquitectura no contemplada: {machine}", file=sys.stderr)
        return 1

    os_primary, os_posix = OS_MACRO.get(platform.system(), (None, None))
    if not os_primary:
        print(f"error: sistema no contemplado: {platform.system()}", file=sys.stderr)
        return 1

    commit = git(engine, "rev-parse", "--short", "HEAD") or "unknown"
    branch = git(engine, "rev-parse", "--abbrev-ref", "HEAD") or "unknown"
    date = git(engine, "log", "-1", "--format=%cs") or "1970-01-01"
    bits = struct.calcsize("P") * 8

    lines = [
        "/* generado por tools/gen_build_h.py - no editar a mano */",
        "#ifndef BUILD_H",
        "#define BUILD_H",
        "",
        f'#define XASH_BUILD_COMMIT "{commit}"',
        f'#define XASH_BUILD_BRANCH "{branch}"',
        f'#define XASH_BUILD_COMMIT_DATE "{date}"',
        "",
        f"#define {arch} 1",
        f"#define {os_primary} 1",
    ]
    if os_posix:
        lines.append(f"#define {os_posix} 1")
    lines.append("#define XASH_LITTLE_ENDIAN 1"
                 if sys.byteorder == "little" else "#define XASH_BIG_ENDIAN 1")
    if bits == 64:
        lines.append("#define XASH_64BIT 1")
    lines += ["", "#endif /* BUILD_H */", ""]

    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"escrito {out} ({arch}, {os_primary}, {bits} bits, commit {commit})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
