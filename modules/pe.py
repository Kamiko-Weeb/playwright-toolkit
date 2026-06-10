"""
Minimal PE (Windows executable) static analyzer — pure stdlib, no dependencies.

Parses the DOS/PE/optional headers, the section table and the import directory of
a PE file directly from its bytes, then derives two malware-relevant signals:

  * Packing       — a section with very high entropy, a zero-raw/large-virtual
                    section, or a known packer section name (UPX0, .aspack …)
                    indicates the real code is compressed/encrypted on disk.
  * Capability     — the imported Win32 APIs reveal intent. Process injection
                    (VirtualAllocEx + WriteProcessMemory + CreateRemoteThread),
                    download-and-execute (URLDownloadToFile + WinExec), keylogging
                    (SetWindowsHookEx) and similar combinations are strong tells.

This is read-only static analysis: bytes in, findings out. Nothing is executed.
Everything is bounds-checked and wrapped, so a malformed PE yields an empty/partial
result rather than raising.
"""

import struct
from collections import Counter
from hashlib import md5
from math import log2

# APIs grouped by capability. A single import is weak signal; a full group firing
# is a strong one, so callers can weight "N of group" matches.
SUSPICIOUS_APIS = {
    "process-injection": {
        "VirtualAllocEx", "WriteProcessMemory", "CreateRemoteThread",
        "NtCreateThreadEx", "QueueUserAPC", "SetThreadContext",
        "VirtualProtect", "VirtualProtectEx",
    },
    "download-and-execute": {
        "URLDownloadToFile", "URLDownloadToFileA", "URLDownloadToFileW",
        "InternetOpenUrl", "InternetReadFile", "WinExec", "ShellExecuteA",
        "ShellExecuteW", "CreateProcessA", "CreateProcessW",
    },
    "dynamic-resolution": {
        "LoadLibraryA", "LoadLibraryW", "GetProcAddress", "LdrLoadDll",
    },
    "anti-analysis": {
        "IsDebuggerPresent", "CheckRemoteDebuggerPresent",
        "NtQueryInformationProcess", "GetTickCount", "OutputDebugStringA",
    },
    "persistence-keylog": {
        "RegSetValueExA", "RegSetValueExW", "RegCreateKeyExA",
        "SetWindowsHookExA", "SetWindowsHookExW", "GetAsyncKeyState",
    },
}

KNOWN_PACKER_SECTIONS = {
    "UPX0", "UPX1", "UPX2", ".aspack", ".adata", ".nsp0", ".nsp1",
    ".petite", "FSG!", ".themida", ".vmp0", ".vmp1", ".enigma1",
}

SECTION_ENTROPY_PACKED = 7.2  # bits/byte within a single section


def _entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = Counter(data)
    n = len(data)
    return -sum((c / n) * log2(c / n) for c in counts.values())


def is_pe(data: bytes) -> bool:
    return len(data) >= 2 and data[:2] == b"MZ"


def analyze(data: bytes) -> dict:
    """Return {'is_pe', 'machine', 'sections', 'imports', 'findings', 'verdict'}.

    verdict is one of: clean / suspicious / malicious (PE-local; the caller folds
    it into the file's overall verdict). Never raises.
    """
    out = {"is_pe": False, "machine": None, "sections": [],
           "imports": [], "imphash": None, "findings": [], "verdict": "clean"}
    try:
        if not is_pe(data) or len(data) < 64:
            return out
        e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
        if e_lfanew + 24 > len(data) or data[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
            return out
        out["is_pe"] = True

        coff = e_lfanew + 4
        machine, n_sections, _, _, _, opt_size, _ = struct.unpack_from(
            "<HHIIIHH", data, coff)
        out["machine"] = {0x14c: "x86", 0x8664: "x64", 0x1c0: "ARM",
                          0xaa64: "ARM64"}.get(machine, hex(machine))

        opt = coff + 20
        magic = struct.unpack_from("<H", data, opt)[0] if opt + 2 <= len(data) else 0
        is_pe32_plus = magic == 0x20b

        # Data directories start after the fixed optional-header body.
        dd_offset = opt + (112 if is_pe32_plus else 96)
        import_rva = import_size = 0
        if dd_offset + 16 <= len(data):
            # Directory index 1 = import table.
            import_rva, import_size = struct.unpack_from("<II", data, dd_offset + 8)

        # ── Section table ─────────────────────────────────────────────
        sec_table = opt + opt_size
        sections = []
        for i in range(n_sections):
            off = sec_table + i * 40
            if off + 40 > len(data):
                break
            raw = data[off:off + 8]
            name = raw.split(b"\x00", 1)[0].decode("latin-1", "replace")
            vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
            body = data[rawptr:rawptr + rawsize] if rawptr + rawsize <= len(data) else b""
            ent = round(_entropy(body), 2)
            sections.append({"name": name, "vsize": vsize, "vaddr": vaddr,
                             "rawsize": rawsize, "rawptr": rawptr, "entropy": ent})
        out["sections"] = sections

        # ── Packing heuristics ────────────────────────────────────────
        for s in sections:
            if s["name"] in KNOWN_PACKER_SECTIONS:
                out["findings"].append(f"packer section name '{s['name']}'")
                out["verdict"] = "suspicious"
            if s["rawsize"] and s["entropy"] >= SECTION_ENTROPY_PACKED:
                out["findings"].append(
                    f"high-entropy section '{s['name']}' ({s['entropy']}) — packed/encrypted")
                out["verdict"] = "suspicious"
            if s["vsize"] > 0 and s["rawsize"] == 0 and s["vsize"] > 0x1000:
                out["findings"].append(
                    f"section '{s['name']}' has no raw data but large virtual size")
                out["verdict"] = "suspicious"

        # ── Imports ───────────────────────────────────────────────────
        imports = _parse_imports(data, sections, import_rva, import_size)
        out["imports"] = imports
        if imports:
            out["imphash"] = compute_imphash(imports)
        imported = {fn for _, fns in imports for fn in fns}
        hits_by_group = {}
        for group, apis in SUSPICIOUS_APIS.items():
            matched = sorted(imported & apis)
            if matched:
                hits_by_group[group] = matched

        # A full injection or download-exec combo is the strongest tell.
        for strong in ("process-injection", "download-and-execute"):
            if len(hits_by_group.get(strong, [])) >= 2:
                out["findings"].append(
                    f"{strong} API combo: {', '.join(hits_by_group[strong])}")
                out["verdict"] = "malicious"
        for group, matched in hits_by_group.items():
            if group not in ("process-injection", "download-and-execute"):
                out["findings"].append(f"{group} API: {', '.join(matched)}")
                if out["verdict"] == "clean":
                    out["verdict"] = "suspicious"

    except Exception as e:  # malformed PE — return whatever we gathered
        out["findings"].append(f"pe-parse: partial ({e})")
    return out


def _rva_to_offset(rva: int, sections: list[dict]) -> int | None:
    for s in sections:
        start = s["vaddr"]
        end = start + max(s["vsize"], s["rawsize"])
        if start <= rva < end:
            return s["rawptr"] + (rva - start)
    return None


def _read_cstr(data: bytes, off: int, limit: int = 256) -> str:
    end = data.find(b"\x00", off, off + limit)
    if end == -1:
        end = min(off + limit, len(data))
    return data[off:end].decode("latin-1", "replace")


def _parse_imports(data: bytes, sections: list[dict],
                   import_rva: int, import_size: int) -> list[tuple[str, list[str]]]:
    """Walk the import directory → [(dll_name, [function names]), ...]. Best-effort."""
    result: list[tuple[str, list[str]]] = []
    if not import_rva:
        return result
    base = _rva_to_offset(import_rva, sections)
    if base is None:
        return result

    # Each import descriptor is 20 bytes; table ends at an all-zero descriptor.
    for i in range(256):  # hard cap on number of imported DLLs
        desc = base + i * 20
        if desc + 20 > len(data):
            break
        orig_thunk, _, _, name_rva, first_thunk = struct.unpack_from("<IIIII", data, desc)
        if orig_thunk == 0 and name_rva == 0 and first_thunk == 0:
            break
        name_off = _rva_to_offset(name_rva, sections)
        dll = _read_cstr(data, name_off) if name_off is not None else "?"

        thunk_rva = orig_thunk or first_thunk
        thunk_off = _rva_to_offset(thunk_rva, sections) if thunk_rva else None
        funcs: list[str] = []
        if thunk_off is not None:
            for j in range(2048):  # cap functions per DLL
                t = thunk_off + j * 4  # 32-bit thunks (good enough for name extraction)
                if t + 4 > len(data):
                    break
                val = struct.unpack_from("<I", data, t)[0]
                if val == 0:
                    break
                if val & 0x80000000:  # import by ordinal — record as ord<N>
                    funcs.append(f"ord{val & 0xffff}")
                    continue
                hint_off = _rva_to_offset(val, sections)
                if hint_off is not None and hint_off + 2 < len(data):
                    funcs.append(_read_cstr(data, hint_off + 2))
        result.append((dll, funcs))
    return result


def compute_imphash(imports: list[tuple[str, list[str]]]) -> str:
    """Import hash (Mandiant-style): MD5 over 'lib.func' pairs in import order.

    Different malware samples built from the same source share an import table,
    so they share an imphash even when their file hashes differ — letting one
    signature catch a whole family / variants.
    """
    parts = []
    for dll, funcs in imports:
        lib = dll.lower()
        for ext in (".dll", ".ocx", ".sys"):
            if lib.endswith(ext):
                lib = lib[:-4]
                break
        for fn in funcs:
            parts.append(f"{lib}.{fn.lower()}")
    return md5(",".join(parts).encode()).hexdigest()
