#!/usr/bin/env python3
"""Range-extract boot.img kernel from an official HyperOS OTA zip.

No full download: reads ZIP64 EOCD + central directory + payload.bin manifest
over HTTP Range requests, then fetches only the boot partition's header and
kernel slice.
"""
import json
import struct
import sys
import urllib.request

URL = ("https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/"
       "OS4.0.0.19.XODCNXM/dijun-ota_full-OS4.0.0.19.XODCNXM-user-17.0-aa6a58e947.zip")
TOTAL = 7_821_662_782
UA = {"User-Agent": "Mozilla/5.0"}


def rng(a, b):
    """Inclusive byte range."""
    h = dict(UA)
    h["Range"] = f"bytes={a}-{b}"
    req = urllib.request.Request(URL, headers=h)
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if len(data) != b - a + 1:
        raise RuntimeError(f"short read {len(data)} != {b-a+1}")
    return data


def varint(buf, i):
    shift = 0
    val = 0
    while True:
        b = buf[i]
        i += 1
        val |= (b & 0x7F) << shift
        if not b & 0x80:
            return val, i
        shift += 7


def pbfields(buf):
    i = 0
    out = []
    n = len(buf)
    while i < n:
        key, i = varint(buf, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(buf, i)
        elif wt == 2:
            ln, i = varint(buf, i)
            v = buf[i:i + ln]
            i += ln
        elif wt == 5:
            v = buf[i:i + 4]
            i += 4
        elif wt == 1:
            v = buf[i:i + 8]
            i += 8
        else:
            raise RuntimeError(f"wiretype {wt}")
        out.append((fn, v))
    return out


def find_zip64(tail, tail_start):
    """Return (cd_offset, cd_size, total_entries) resolving ZIP64."""
    idx = tail.rfind(b"PK\x05\x06")
    if idx < 0:
        raise RuntimeError("no EOCD")
    eocd = tail[idx:idx + 22]
    _, _, _, n_this, n_tot, cd_size, cd_off, _ = struct.unpack("<IHHHHIIH", eocd)
    if n_tot != 0xFFFF and cd_off != 0xFFFFFFFF:
        return cd_off, cd_size, n_tot
    loc = tail.rfind(b"PK\x06\x07")
    if loc < 0:
        raise RuntimeError("no zip64 locator")
    z_off = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
    rec = rng(z_off, z_off + 55)
    if rec[:4] != b"PK\x06\x06":
        raise RuntimeError("bad zip64 EOCD")
    fields = struct.unpack("<QHHIIQQQQ", rec[4:56])
    # [0]=rec size, [1]=ver made, [2]=ver need, [3]=disk, [4]=cd disk,
    # [5]=n_this, [6]=n_total, [7]=cd_size, [8]=cd_offset
    return fields[8], fields[7], fields[6]


def central_entry(name_wanted, cd):
    i = 0
    while i < len(cd):
        if cd[i:i + 4] != b"PK\x01\x02":
            break
        (_, _, _, _, _, _, _, _, csize, usize, nlen, elen, clen, _, _, _, lho) = \
            struct.unpack("<IHHHHHHIIIHHHHHII", cd[i:i + 46])
        name = cd[i + 46:i + 46 + nlen].decode("utf-8", "replace")
        extra = cd[i + 46 + nlen:i + 46 + nlen + elen]
        # resolve zip64 extra when needed
        if lho == 0xFFFFFFFF or csize == 0xFFFFFFFF or usize == 0xFFFFFFFF:
            j = 0
            while j + 4 <= len(extra):
                hid, hsz = struct.unpack("<HH", extra[j:j + 4])
                body = extra[j + 4:j + 4 + hsz]
                if hid == 0x0001:
                    k = 0
                    if usize == 0xFFFFFFFF:
                        usize = struct.unpack("<Q", body[k:k + 8])[0]; k += 8
                    if csize == 0xFFFFFFFF:
                        csize = struct.unpack("<Q", body[k:k + 8])[0]; k += 8
                    if lho == 0xFFFFFFFF:
                        lho = struct.unpack("<Q", body[k:k + 8])[0]; k += 8
                j += 4 + hsz
        if name == name_wanted:
            return name, lho, csize, usize
        i += 46 + nlen + elen + clen
    raise RuntimeError(f"entry {name_wanted} not found")


def local_data_offset(lho):
    lh = rng(lho, lho + 29)
    nlen, elen = struct.unpack("<HH", lh[26:30])
    return lho + 30 + nlen + elen


def main():
    tail_len = 200_000
    tail = rng(TOTAL - tail_len, TOTAL - 1)
    cd_off, cd_size, n = find_zip64(tail, TOTAL - tail_len)
    print(f"[*] zip64: cd_off={cd_off} cd_size={cd_size} entries={n}")

    cd = rng(cd_off, cd_off + cd_size - 1)
    name, lho, csize, usize = central_entry("payload.bin", cd)
    print(f"[*] {name}: local={lho} csize={csize} usize={usize}")
    p_start = local_data_offset(lho)
    print(f"[*] payload data starts at {p_start}")

    hdr = rng(p_start, p_start + 23)
    if hdr[:4] != b"CrAU":
        raise RuntimeError(f"bad payload magic {hdr[:4]!r}")
    version = struct.unpack(">Q", hdr[4:12])[0]
    manifest_size = struct.unpack(">Q", hdr[12:20])[0]
    sig_size = struct.unpack(">I", hdr[20:24])[0] if version >= 2 else 0
    print(f"[*] payload v{version} manifest={manifest_size} meta_sig={sig_size}")

    manifest = rng(p_start + 24, p_start + 24 + manifest_size - 1)
    mf = pbfields(manifest)
    block_size = 4096
    for fn, v in mf:
        if fn == 3:
            block_size = v
    parts = [v for fn, v in mf if fn == 13]
    print(f"[*] block_size={block_size} partitions={len(parts)}")

    data_off = p_start + 24 + manifest_size + sig_size
    cur = data_off
    found = None
    for p in parts:
        pf = pbfields(p)
        pname = ""
        ops = []
        for fn, v in pf:
            if fn == 1:
                pname = v.decode()
            elif fn == 8:
                ops.append(v)
        total = 0
        for op in ops:
            of = pbfields(op)
            otype = 0
            dlen = None
            dst_blocks = 0
            for fn, v in of:
                if fn == 1:
                    otype = v
                elif fn == 3:
                    dlen = v
                elif fn == 6:  # Extent message {start_block=1, num_blocks=2}
                    for efn, ev in pbfields(v):
                        if efn == 2:
                            dst_blocks += ev
            if otype in (6, 7):  # ZERO / DISCARD carry no data
                dl = 0
            elif dlen is not None:
                dl = dlen
            else:
                dl = dst_blocks * block_size
            total += dl
        print(f"    {pname:<16} data={total/1048576:8.2f} MB  ops={len(ops)}")
        if pname == "boot":
            found = (cur, total)
        cur += total

    if not found:
        raise RuntimeError("boot partition not in manifest")
    boff, blen = found
    print(f"[*] boot offset={boff} len={blen}")

    bh = rng(boff, boff + 4095)
    if bh[:8] != b"ANDROID!":
        print("[!] unexpected boot magic:", bh[:8])
    ksize, rsize, osver, hsize = struct.unpack("<IIII", bh[8:24])
    hver = struct.unpack("<I", bh[40:44])[0]
    print(f"[*] boot: kernel={ksize/1048576:.2f} MB ramdisk={rsize/1048576:.2f} MB "
          f"hdr={hsize} hdr_version={hver}")
    k_off = (hsize + 4095) & ~4095
    print(f"[*] kernel at +{k_off}")
    kern = rng(boff + k_off, boff + k_off + ksize - 1)
    print(f"[*] kernel magic: {kern[:4].hex()}")
    with open("kernel_image.bin", "wb") as f:
        f.write(kern)
    json.dump({"boot_offset": boff, "boot_len": blen, "kernel_size": ksize,
               "kernel_file": "kernel_image.bin", "header_version": hver},
              open("extract.json", "w"), indent=2)
    print("[+] wrote kernel_image.bin")


if __name__ == "__main__":
    sys.exit(main())
