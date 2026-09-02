#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""造一个最小的假 Claude.app，供回归测试使用。

为什么不直接拿真的 Claude 测：一次 ditto 备份要 800MB / 一分钟，跑一轮测试
就得好几分钟；而且真 app 一旦被测试改坏，用户的日常应用就废了。假 app 只有
几十 KB，install/uninstall 全流程两秒跑完，坏了删掉重造即可。

结构照抄真 app 里 clfont 实际接触到的那几处：
  Contents/Info.plist                  含 ElectronAsarIntegrity:Resources/app.asar:hash
  Contents/Resources/app.asar          含 .vite/build/mainView.js 与 renderer 的 index.html
  Contents/MacOS/Claude                能活着的真二进制（冒烟测试要按路径在 ps 里认出它）
"""

import hashlib
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
from pathlib import Path

BLOCK = 4194304


def integrity(buf):
    blocks = [hashlib.sha256(buf[i:i + BLOCK]).hexdigest()
              for i in range(0, len(buf), BLOCK)] or [hashlib.sha256(b"").hexdigest()]
    return {"algorithm": "SHA256", "hash": hashlib.sha256(buf).hexdigest(),
            "blockSize": BLOCK, "blocks": blocks}


def build_asar(files):
    """files: {"/a/b.js": b"..."} -> asar 字节串。格式与 clfont 的 asar_pack 一致。"""
    root = {"files": {}}
    blobs, cursor = [], 0
    for rel in sorted(files):
        data = files[rel]
        node = root
        parts = rel.strip("/").split("/")
        for part in parts[:-1]:
            node = node["files"].setdefault(part, {"files": {}})
        node["files"][parts[-1]] = {
            "offset": str(cursor), "size": len(data), "integrity": integrity(data)}
        blobs.append(data)
        cursor += len(data)
    hdr = json.dumps(root, separators=(",", ":"), ensure_ascii=False).encode()
    jl = len(hdr)
    inner = (4 + jl + 3) // 4 * 4
    outer = 4 + inner
    return (struct.pack("<IIII", 4, outer, inner, jl) + hdr
            + b"\0" * (inner - 4 - jl) + b"".join(blobs))


def header_hash(asar_bytes):
    _, _, _, jl = struct.unpack("<IIII", asar_bytes[:16])
    return hashlib.sha256(asar_bytes[16:16 + jl]).hexdigest()


# 真的 mainView.js 结尾是 sourceMappingURL 注释——clfont 的注入必须以换行开头
# 才不会被它吃掉。夹具照样带上，这样这条约束在测试里是活的。
# clfont 会粗校验 preload：必须出现 ipcRenderer/contextBridge，且不得含主进程
# 特征（app.whenReady 等）。夹具照这个约束造，才能测到真实路径。
# 结尾的 sourceMappingURL 注释也照留：clfont 的注入必须以换行开头，否则整行
# 会被这条行注释吃掉——这个坑真出现过，让它在测试里活着。
PRELOAD = (b"'use strict';\n"
           b"const {contextBridge, ipcRenderer} = require('electron');\n"
           b"contextBridge.exposeInMainWorld('x', {p: () => ipcRenderer.invoke('p')});\n"
           b"//# sourceMappingURL=mainView.js.map")   # 真文件结尾没有换行

# 主进程入口的样子。clfont 绝不能碰它，测试里用来验证「没被改过」。
MAIN_JS = (b"'use strict';\n"
           b"const {app, BrowserWindow} = require('electron');\n"
           b"app.whenReady().then(() => { new BrowserWindow({}); });\n")
INDEX = b"<!doctype html><html><head><title>Claude</title></head><body></body></html>"

MAIN_C = r"""
#include <unistd.h>
int main(void) { sleep(120); return 0; }
"""


def make_app(dest, version="1.0.0"):
    """在 dest 处造出可用的假 .app（已 ad-hoc 签名）。返回 Path。"""
    dest = Path(dest)
    shutil.rmtree(dest, ignore_errors=True)
    (dest / "Contents/MacOS").mkdir(parents=True)
    (dest / "Contents/Resources").mkdir(parents=True)

    asar = build_asar({"/.vite/build/mainView.js": PRELOAD,
                       "/.vite/build/index.pre.js": MAIN_JS,
                       "/.vite/renderer/main_window/index.html": INDEX})
    (dest / "Contents/Resources/app.asar").write_bytes(asar)

    plist = {
        "CFBundleName": "Claude",
        "CFBundleIdentifier": "com.example.clfont.fixture",
        "CFBundleExecutable": "Claude",
        "CFBundleShortVersionString": version,
        "CFBundlePackageType": "APPL",
        "ElectronAsarIntegrity": {
            "Resources/app.asar": {"algorithm": "SHA256",
                                   "hash": header_hash(asar)},
        },
    }
    with open(dest / "Contents/Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    # 冒烟测试按 ps 里的完整路径认进程，所以必须是真二进制而不是脚本
    # （脚本的 comm 会显示成解释器路径，认不出来）
    src = dest / "Contents/MacOS/main.c"
    src.write_text(MAIN_C)
    subprocess.run(["cc", "-o", str(dest / "Contents/MacOS/Claude"), str(src)],
                   check=True, capture_output=True)
    src.unlink()

    subprocess.run(["codesign", "--force", "--sign", "-", str(dest)],
                   check=True, capture_output=True)
    return dest


if __name__ == "__main__":
    p = make_app(sys.argv[1] if len(sys.argv) > 1 else "/tmp/FakeClaude.app")
    print("已生成", p)
