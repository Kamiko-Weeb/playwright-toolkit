"""Synthetic PE builder for tests — constructs minimal but well-formed PE bytes
with chosen sections and (optionally) an import table, so the analyzer can be
tested without shipping real executables."""

import struct


def build_pe(sections, imports=None, pe32_plus=False) -> bytes:
    """sections: list of (name, body_bytes). imports: {dll: [func, ...]}.

    pe32_plus=True emits a 64-bit (PE32+) binary: magic 0x20b, data directories
    at optional-header offset 112, and 8-byte import thunks.
    """
    e_lfanew = 0x40
    dos = bytearray(0x40)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, e_lfanew)
    opt_size = 0xF0 if pe32_plus else 0xE0
    dd_base = 112 if pe32_plus else 96
    thunk_size = 8 if pe32_plus else 4
    thunk_fmt = "<Q" if pe32_plus else "<I"
    magic = 0x20b if pe32_plus else 0x10b

    secs = list(sections)
    sec_table_off = e_lfanew + 4 + 20 + opt_size
    n_sections = len(secs) + (1 if imports else 0)
    headers_size = sec_table_off + n_sections * 40

    placed = []
    cur = headers_size
    for idx, (name, body) in enumerate(secs):
        placed.append([name, body, 0x1000 * (idx + 1), cur])
        cur += len(body)

    import_rva = import_size = 0
    if imports:
        V, R = 0x1000 * (len(secs) + 1), cur
        ndll = len(imports)
        desc_area = 20 * (ndll + 1)
        descriptors = bytearray()
        tail = bytearray()
        for dll, funcs in imports.items():
            name_k = desc_area + len(tail)
            tail += dll.encode() + b"\x00"
            hint_offs = []
            for fn in funcs:
                if (desc_area + len(tail)) % 2:
                    tail += b"\x00"
                hint_offs.append(desc_area + len(tail))
                tail += struct.pack("<H", 0) + fn.encode() + b"\x00"
            while (desc_area + len(tail)) % thunk_size:
                tail += b"\x00"
            ilt_k = desc_area + len(tail)
            for ho in hint_offs:
                tail += struct.pack(thunk_fmt, V + ho)
            tail += struct.pack(thunk_fmt, 0)
            descriptors += struct.pack("<IIIII", V + ilt_k, 0, 0, V + name_k, V + ilt_k)
        descriptors += b"\x00" * 20
        placed.append([".idata", bytes(descriptors + tail), V, R])
        import_rva, import_size = V, desc_area

    coff = struct.pack("<HHIIIHH", 0x8664 if pe32_plus else 0x14c,
                       len(placed), 0, 0, 0, opt_size, 0x102)
    opt = bytearray(opt_size)
    struct.pack_into("<H", opt, 0, magic)
    if import_rva:
        struct.pack_into("<II", opt, dd_base + 8, import_rva, import_size)

    sec_entries = bytearray()
    body_area = bytearray()
    cur = headers_size
    for name, body, vaddr, _ in placed:
        nm = name.encode()[:8].ljust(8, b"\x00")
        sec_entries += nm + struct.pack("<IIII", max(len(body), 0x1000),
                                        vaddr, len(body), cur) + b"\x00" * 16
        body_area += body
        cur += len(body)

    return bytes(dos) + b"PE\x00\x00" + coff + bytes(opt) + \
        bytes(sec_entries) + bytes(body_area)
