#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""clfont 的回归测试。无第三方依赖，直接 python3 tests/test_clfont.py 运行。

存在的理由：CLI 里全是危险操作（改 asar、改 Info.plist、重签名、事务回滚），
在此之前一个测试都没有，全靠手测。把现有行为固化下来，Swift 重写版才有得对照
——重写的验收标准就是「这套测试全绿」。

分两层：
  纯函数层  直接 import clfont 调函数，毫秒级
  端到端层  对 tests/fixture.py 造的假 app 跑真命令，每个约 10 秒
           （其中 6 秒是冒烟测试观察进程存活，那是被测行为的一部分，不能省）
"""

import importlib.machinery
import importlib.util
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
import fixture  # noqa: E402

GOLDEN = ROOT / "tests" / "golden"
UPDATE_GOLDEN = os.environ.get("UPDATE_GOLDEN") == "1"


def load_cli():
    loader = importlib.machinery.SourceFileLoader("clfont_mod", str(ROOT / "clfont"))
    spec = importlib.util.spec_from_loader("clfont_mod", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


M = load_cli()

# ---------------------------------------------------------------- 迷你测试框架

_TESTS = []
_FAILED = []


def test(fn):
    _TESTS.append(fn)
    return fn


def eq(got, want, what=""):
    if got != want:
        raise AssertionError(f"{what}\n  实际: {got!r}\n  期望: {want!r}")


def ok(cond, what=""):
    if not cond:
        raise AssertionError(what or "断言失败")


def contains(hay, needle, what=""):
    if needle not in hay:
        raise AssertionError(f"{what}\n  没找到: {needle!r}\n  在: {hay[:400]!r}")


def golden(name, actual):
    """黄金文件比对。UPDATE_GOLDEN=1 时改为写入（改动行为后请人工复核 diff）。"""
    GOLDEN.mkdir(parents=True, exist_ok=True)
    path = GOLDEN / name
    if UPDATE_GOLDEN or not path.exists():
        path.write_text(actual)
        print(f"    （已写入黄金文件 {name}）")
        return
    want = path.read_text()
    if actual != want:
        raise AssertionError(
            f"与黄金文件 {name} 不符。确认是有意改动后跑 UPDATE_GOLDEN=1 更新。\n"
            f"  实际长度 {len(actual)}，期望 {len(want)}")


# ---------------------------------------------------------------- 沙盒

class Sandbox:
    """一套隔离的环境：假 app + 独立的数据目录/配置/自安装目录。
    绝不碰用户真实的 Claude、备份和配置。"""

    def __init__(self, version="1.0.0"):
        self.dir = Path(tempfile.mkdtemp(prefix="clfont-test-"))
        self.app = fixture.make_app(self.dir / "FakeClaude.app", version)
        self.env = dict(os.environ)
        self.env.update({
            "CLFONT_DATA_DIR": str(self.dir / "data"),
            "CLFONT_CONFIG": str(self.dir / "config.json"),
            "CLFONT_BIN_DIR": str(self.dir / "bin"),
            "CLFONT_SMOKE_USER_DATA_DIR": str(self.dir / "smoke"),
        })

    def run(self, *args, expect=0, **envkw):
        env = dict(self.env)
        env.update({k: str(v) for k, v in envkw.items()})
        r = subprocess.run(
            [sys.executable, str(ROOT / "clfont"), "--app", str(self.app)] + list(args),
            capture_output=True, text=True, env=env)
        out = r.stdout + r.stderr
        if expect is not None and r.returncode != expect:
            raise AssertionError(
                f"退出码 {r.returncode}，期望 {expect}\n{out[-1500:]}")
        return r.returncode, out

    @property
    def asar(self):
        return self.app / "Contents/Resources/app.asar"

    def plist_hash(self):
        with open(self.app / "Contents/Info.plist", "rb") as f:
            d = plistlib.load(f)
        return d["ElectronAsarIntegrity"]["Resources/app.asar"]["hash"]

    def asar_file(self, rel):
        """从 asar 里取出某个文件的字节内容。"""
        raw = self.asar.read_bytes()
        _, _, _, jl = struct.unpack("<IIII", raw[:16])
        hdr = json.loads(raw[16:16 + jl])
        base = 8 + (4 + ((4 + jl + 3) // 4 * 4))
        node = hdr
        for part in rel.strip("/").split("/"):
            node = node["files"][part]
        off = int(node["offset"])
        return raw[base + off:base + off + node["size"]]

    def sig_valid(self):
        return subprocess.run(["codesign", "-v", str(self.app)],
                              capture_output=True).returncode == 0

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


# ---------------------------------------------------------------- 纯函数层

@test
def test_css_cjk_only():
    """只换中文：应有 ClaudeCJKSerif + CDS 变量，且不含拉丁段。"""
    M.set_app("/tmp/x.app")
    cfg = dict(M.DEFAULT_CONFIG, scope="cjk", font="Songti SC")
    css = M.build_css("auto", cfg)
    contains(css, "ClaudeCJKSerif", "中文模式应注入 ClaudeCJKSerif")
    ok("U+0020-007E" not in css, "只换中文时不该出现拉丁码位")
    golden("css_cjk.css", css)


@test
def test_css_both_with_everything():
    """全开：中英文 + 字号 + 代码块字体 + 底色。"""
    M.set_app("/tmp/x.app")
    cfg = dict(M.DEFAULT_CONFIG, scope="both", font="Songti SC",
               font_latin="Times New Roman", font_scale=120,
               font_scale_latin=90, font_mono="Menlo", font_mono_scale=110,
               bg_color="#F0EEE6")
    css = M.build_css("auto", cfg)
    golden("css_all.css", css)


@test
def test_latin_ext_only_for_body_font():
    """重音字母区只给正文字体放开；承载图标的界面字体必须不含。"""
    M.set_app("/tmp/x.app")
    cfg = dict(M.DEFAULT_CONFIG, scope="latin", font_latin="Times New Roman")
    css = M.build_css("auto", cfg)
    import re
    faces = re.findall(r'@font-face\{[^}]*\}', css)
    serif = [f for f in faces if '"anthropic-serif"' in f]
    sans = [f for f in faces if '"anthropic-sans"' in f]
    ok(serif and all("U+00C0-00FF" in f for f in serif),
       "anthropic-serif 应覆盖重音字母区")
    ok(sans and not any("U+00C0-00FF" in f for f in sans),
       "anthropic-sans（承载图标）绝不能覆盖重音字母区")


@test
def test_background_needs_important_and_cds_prefix():
    """底色两个必要条件：--cds- 前缀 + !important。实测得出，回退了就白改。"""
    M.set_app("/tmp/x.app")
    cfg = dict(M.DEFAULT_CONFIG, bg_color="#F0EEE6")
    css = M.background_css(cfg)
    contains(css, "--cds-surface-0", "必须用带 --cds- 前缀的变量名")
    contains(css, "!important", "不加 !important 会被后加载的样式表赢回去")
    contains(css, 'data-mode="dark"', "必须把深色模式排除在外")
    ok("--surface-0:" not in css.replace("--cds-surface-0:", ""),
       "不该再用本地外壳那套无前缀变量名")


@test
def test_background_rejects_bad_color():
    M.set_app("/tmp/x.app")
    eq(M.background_css(dict(M.DEFAULT_CONFIG, bg_color="red")), "", "非法色值应被忽略")
    eq(M.background_css(dict(M.DEFAULT_CONFIG, bg_color="")), "", "空值不注入")


@test
def test_scale_clamped():
    for raw, want in [(10, 80), (999, 150), ("abc", 100), (None, 100), (115, 115)]:
        eq(M._scale({"font_scale": raw}, "font_scale"), want, f"字号 {raw!r} 钳制")


@test
def test_entitlements_filter():
    """与开发者身份绑定的项必须剔除，ad-hoc 下留着可能让 AMFI 拒掉整份。"""
    src = {"com.apple.security.virtualization": True,
           "com.apple.security.cs.allow-jit": True,
           "com.apple.application-identifier": "TEAM.app",
           "keychain-access-groups": ["TEAM.g"],
           "com.apple.developer.team-identifier": "TEAM"}
    kept = {k: v for k, v in src.items()
            if k not in M.ENT_DROP and not k.startswith(M.ENT_DROP_PREFIX)}
    eq(sorted(kept), ["com.apple.security.cs.allow-jit",
                      "com.apple.security.virtualization"], "保留项")


@test
def test_backup_naming_per_target():
    """默认目标保持老命名；其它目标加路径哈希，否则两者会按版本号撞车。"""
    M.set_app("/Applications/Claude.app")
    eq(M.target_slug(), "", "默认目标不加后缀")
    eq(M.backup_path("9.9.9").name, "Claude-backup-9.9.9.app")
    M.set_app("/tmp/Other.app")
    ok(M.target_slug().startswith("-"), "非默认目标应有后缀")
    ok(M.backup_path("9.9.9").name.startswith("Claude-backup-9.9.9-"))


@test
def test_last_install_per_target():
    """配置只有一份、两个目标共用，记录必须分开存。"""
    M.set_app("/Applications/Claude.app")
    cfg = {}
    M.last_install_set(cfg, {"version": "1"})
    M.set_app("/tmp/Other.app")
    eq(M.last_install_get(cfg), {}, "另一个目标不该读到默认目标的记录")
    M.last_install_set(cfg, {"version": "2"})
    M.set_app("/Applications/Claude.app")
    eq(M.last_install_get(cfg)["version"], "1", "默认目标的记录不该被覆盖")


@test
def test_preload_heuristic():
    ok(M._is_renderer_preload(fixture.PRELOAD), "应认出 renderer preload")
    ok(not M._is_renderer_preload(fixture.MAIN_JS), "绝不能把主进程认成 preload")


@test
def test_asar_roundtrip_byte_identical():
    """原样重打包必须与原文件逐字节一致——整个方案的地基。"""
    tmp = Path(tempfile.mkdtemp(prefix="clfont-asar-"))
    try:
        src = tmp / "a.asar"
        src.write_bytes(fixture.build_asar(
            {"/.vite/build/mainView.js": fixture.PRELOAD,
             "/.vite/renderer/main_window/index.html": fixture.INDEX}))
        header, base = M.asar_read_header(src)
        f = open(src, "rb")
        try:
            def get(sub, key):
                f.seek(base + key[0])
                return f.read(key[1])
            M.asar_pack(header, get, tmp / "b.asar")
        finally:
            f.close()
        eq((tmp / "b.asar").read_bytes(), src.read_bytes(), "往返应逐字节一致")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 端到端层

@test
def test_install_then_uninstall_restores_bytes():
    sb = Sandbox()
    try:
        before = sb.asar.read_bytes()
        before_hash = sb.plist_hash()
        sb.run("install", "--yes", "--scope", "cjk")

        ok(M.MARKER.encode() in sb.asar_file("/.vite/build/mainView.js"),
           "preload 应含注入标记")
        eq(sb.asar_file("/.vite/build/index.pre.js"), fixture.MAIN_JS,
           "主进程文件必须原样不动")
        ok(sb.plist_hash() != before_hash, "完整性哈希应已同步为新值")
        ok(sb.sig_valid(), "打完补丁签名应有效")
        ok(list((sb.dir / "data").glob("Claude-backup-*.app")), "应留下整包备份")

        sb.run("uninstall", "--yes")
        eq(sb.asar.read_bytes(), before, "还原后 asar 应与原文件逐字节一致")
        eq(sb.plist_hash(), before_hash, "还原后哈希应回到原值")
        ok(sb.sig_valid(), "还原后签名应有效")
    finally:
        sb.cleanup()


@test
def test_install_is_idempotent():
    sb = Sandbox()
    try:
        sb.run("install", "--yes", "--scope", "cjk")
        first = sb.asar.read_bytes()
        sb.run("install", "--yes", "--scope", "cjk")
        eq(sb.asar.read_bytes(), first, "重复安装应得到相同结果，而不是叠加注入")
    finally:
        sb.cleanup()


@test
def test_rollback_when_smoke_fails():
    """冒烟失败 = 补丁有害，必须回滚到原样。"""
    sb = Sandbox()
    try:
        before = sb.asar.read_bytes()
        code, out = sb.run("install", "--yes", expect=1, CLFONT_SMOKE_FORCE_FAIL="1")
        contains(out, "已回滚到原始状态", "应完成回滚")
        eq(sb.asar.read_bytes(), before, "回滚后应逐字节还原")
        ok(sb.sig_valid(), "回滚后签名应有效")
        ok(not (sb.dir / "data" / "journal.json").exists(), "回滚成功应清掉事务日志")
    finally:
        sb.cleanup()


@test
def test_rollback_at_every_crash_point():
    """在每个注入点自杀，都得能靠 uninstall 修回原样。"""
    for tag in ("after-backup", "after-patch", "after-move",
                "after-rename", "before-resign", "before-smoke"):
        sb = Sandbox()
        try:
            before = sb.asar.read_bytes()
            sb.run("install", "--yes", expect=None, CLFONT_CRASH_AT=tag)
            sb.run("uninstall", "--yes", expect=None)
            eq(sb.asar.read_bytes(), before, f"在 {tag} 崩溃后应能修回原样")
            ok(sb.sig_valid(), f"在 {tag} 崩溃并修复后签名应有效")
        finally:
            sb.cleanup()


@test
def test_refuses_when_nothing_to_apply():
    sb = Sandbox()
    try:
        code, out = sb.run("install", "--yes", "--scope", "latin", expect=1)
        contains(out, "没有任何可应用的设置", "没字体又没底色时应拒绝执行")
    finally:
        sb.cleanup()


@test
def test_status_markers_the_gui_parses():
    """GUI 靠这些字面量解析状态。改了措辞而不同步改 GUI，状态会静默失效——
    这条测试就是那份契约。对应 gui/ClfontApp.swift 的 CLIMarker。"""
    sb = Sandbox()
    try:
        _, out = sb.run("status")
        for mk in ("Claude 版本：", "整包备份：", "字体 "):
            contains(out, mk, "status 缺少 GUI 依赖的标记")
        sb.run("install", "--yes", "--scope", "cjk")
        _, out = sb.run("status")
        contains(out, "已打补丁", "打过补丁后应有此标记")
        _, out = sb.run("doctor", expect=None)
        contains(out, "Helper 权限", "doctor 应报告 Helper 权限")
    finally:
        sb.cleanup()


@test
def test_stale_detection_after_version_bump():
    """Claude 更新会覆盖补丁；status 必须报出来，GUI 才能提示重新应用。"""
    sb = Sandbox()
    try:
        sb.run("install", "--yes", "--scope", "cjk")
        # 模拟 Claude 自动更新：换个版本号，asar 换回原版
        fixture.make_app(sb.app, version="2.0.0")
        _, out = sb.run("status")
        contains(out, "补丁已失效", "版本变了应报补丁失效")
        contains(out, "2.0.0")
    finally:
        sb.cleanup()


@test
def test_uninstall_clears_stale_record():
    """主动还原之后不该再提示「补丁失效，去重新应用」。"""
    sb = Sandbox()
    try:
        sb.run("install", "--yes", "--scope", "cjk")
        sb.run("uninstall", "--yes")
        fixture.make_app(sb.app, version="2.0.0")
        _, out = sb.run("status")
        ok("补丁已失效" not in out, "还原过就不该再报失效")
    finally:
        sb.cleanup()


@test
def test_asar_roundtrip_with_shared_blocks_and_odd_order():
    """asar_pack 最容易写错的两处：内容块去重、按 offset 而非文件名排序。

    真 asar 里相同内容（比如同一个 woff2）会被多个条目共享同一 (offset,size)，
    且条目在 header 里的出现顺序与 offset 顺序无关。这里手工造出这两种情况。"""
    tmp = Path(tempfile.mkdtemp(prefix="clfont-asar2-"))
    try:
        # 三块内容，故意让 header 里的名字顺序与 offset 顺序相反；
        # z.bin 与 a.bin 共享同一块（模拟去重）
        blob0, blob1 = b"AAAA-first", b"BBBBBBBB-second"
        body = blob0 + blob1
        # 名字顺序必须与 offset 顺序**相反**，否则「按名字排」和「按 offset 排」
        # 会得到同样结果，这条测试就形同虚设（第一版就栽在这里）。
        hdr = {"files": {
            "z.bin": {"offset": "0", "size": len(blob0)},
            "a.bin": {"offset": "10", "size": len(blob1)},
            "dup.bin": {"offset": "0", "size": len(blob0)},   # 与 z.bin 同块
        }}
        hj = json.dumps(hdr, separators=(",", ":")).encode()
        jl = len(hj); inner = (4 + jl + 3) // 4 * 4
        raw = struct.pack("<IIII", 4, 4 + inner, inner, jl) + hj + b"\0" * (inner - 4 - jl) + body
        src = tmp / "a.asar"; src.write_bytes(raw)

        header, base = M.asar_read_header(src)
        f = open(src, "rb")
        try:
            def get(sub, key):
                f.seek(base + key[0]); return f.read(key[1])
            M.asar_pack(header, get, tmp / "b.asar")
        finally:
            f.close()
        eq((tmp / "b.asar").read_bytes(), raw, "含共享块、乱序 offset 时仍应逐字节一致")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_asar_pack_refuses_to_edit_shared_block():
    """改一个被多个条目共享的内容块会殃及其它文件，必须拒绝而不是默默改坏。"""
    tmp = Path(tempfile.mkdtemp(prefix="clfont-asar3-"))
    try:
        blob = b"SHARED"
        hdr = {"files": {"a.bin": {"offset": "0", "size": len(blob)},
                         "b.bin": {"offset": "0", "size": len(blob)}}}
        hj = json.dumps(hdr, separators=(",", ":")).encode()
        jl = len(hj); inner = (4 + jl + 3) // 4 * 4
        raw = struct.pack("<IIII", 4, 4 + inner, inner, jl) + hj + b"\0" * (inner - 4 - jl) + blob
        src = tmp / "a.asar"; src.write_bytes(raw)
        header, base = M.asar_read_header(src)
        try:
            M.asar_pack(header, lambda sub, key: b"CHANGED-LONGER", tmp / "b.asar")
        except RuntimeError as e:
            contains(str(e), "共享", "应明确说明拒绝原因")
            return
        raise AssertionError("修改共享块时应当报错，实际却成功了")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


@test
def test_injection_starts_on_its_own_line():
    """注入必须以换行开头。

    mainView.js 结尾是 `//# sourceMappingURL=...` 行注释，注入若紧跟其后，
    整个第一行会被吃进注释里，剩下的括号不配对 → preload 抛语法错 → 界面
    完全不生效。这个坑真踩过两次，用测试钉死。"""
    M.set_app("/tmp/x.app")
    inj = M.build_preload_injection("/* x */")
    ok(inj.startswith("\n"), "注入必须以换行开头，否则会被上一行的行注释吞掉")
    ok(inj.count("(") == inj.count(")"), "括号应配平")
    ok(inj.count("{") == inj.count("}"), "花括号应配平")


@test
def test_patched_preload_survives_line_comment():
    """端到端：打完补丁后，注入的那段不能处在 // 注释行内。"""
    sb = Sandbox()
    try:
        sb.run("install", "--yes", "--scope", "cjk")
        data = sb.asar_file("/.vite/build/mainView.js").decode()
        idx = data.index(M.MARKER)
        line_start = data.rfind("\n", 0, idx) + 1
        line = data[line_start:idx]
        ok("//" not in line, f"注入落在了注释行内：{line!r}")
    finally:
        sb.cleanup()


# ---------------------------------------------------------------- 入口

def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    picked = [f for f in _TESTS if not only or only in f.__name__]
    print(f"运行 {len(picked)} 项测试\n")
    for fn in picked:
        name = fn.__name__
        try:
            fn()
            print(f"  ✓ {name}")
        except Exception as e:
            _FAILED.append(name)
            print(f"  ✗ {name}")
            for line in traceback.format_exc().splitlines()[-6:]:
                print(f"      {line}")
    print()
    if _FAILED:
        print(f"✗ {len(_FAILED)}/{len(picked)} 失败：{'、'.join(_FAILED)}")
        return 1
    print(f"✓ 全部 {len(picked)} 项通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
