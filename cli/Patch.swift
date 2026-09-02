import Foundation

let PRELOAD_REL = "/.vite/build/mainView.js"
let HTML_REL = "/.vite/renderer/main_window/index.html"

/// 构造追加到 preload 尾部的自包含 IIFE：把 CSS 作为 <style> 塞进远程页面，
/// 并**始终保持在 head 末尾**。
///
/// 为什么要保持在末尾：同名家族有多条 @font-face 时，重叠码位上后声明的胜出。
/// claude.ai 是 SPA，会在运行中懒加载 CSS chunk，那些 chunk 里同样声明了
/// anthropic-sans/serif。只插一次就不管的话，后来的声明会把我们在拉丁码位上的
/// 覆盖赢回去——这正是「中文生效、英文不生效」的成因。
///
/// **开头那个换行不能少**：注入点前一行是 `//# sourceMappingURL=...` 行注释，
/// 紧贴着写会让整行被吃进注释里，剩下的括号不配对，preload 直接抛语法错。
func buildPreloadInjection(_ css: String) -> String {
    let b64 = Data(css.utf8).base64EncodedString()
    return "\n;/* \(MARKER) */(function(){try{"
        + "var B=\"\(b64)\";"
        + "var CSS=(function(){try{var s=atob(B),a=new Uint8Array(s.length);"
        + "for(var i=0;i<s.length;i++)a[i]=s.charCodeAt(i);"
        + "return new TextDecoder('utf-8').decode(a);}catch(e){return atob(B);}})();"
        + "var ID=\"\(MARKER)\";var st=null,ob=null;"
        + "function ensure(){try{if(typeof document===\"undefined\")return;"
        + "var r=document.head||document.documentElement;if(!r)return;"
        + "if(!st||!st.isConnected){st=document.getElementById(ID);}"
        + "if(!st){st=document.createElement(\"style\");st.id=ID;"
        + "st.setAttribute(\"data-clfont\",\"1\");st.textContent=CSS;}"
        + "if(r.lastElementChild!==st)r.appendChild(st);"
        + "if(!ob&&typeof MutationObserver!==\"undefined\"){"
        + "ob=new MutationObserver(function(){ensure();});"
        + "ob.observe(r,{childList:true});}}"
        + "catch(e){}}"
        + "ensure();"
        + "try{if(typeof document!==\"undefined\"&&document.addEventListener){"
        + "document.addEventListener(\"DOMContentLoaded\",ensure);"
        + "document.addEventListener(\"load\",ensure,true);}}catch(e){}"
        + "try{if(typeof setInterval!==\"undefined\"){var n=0;var t=setInterval(function(){"
        + "ensure();if(++n>40&&t){clearInterval(t);t=null;}},500);}}catch(e){}"
        + "}catch(e){}})();\n"
}

/// 粗校验：像 preload（有 ipcRenderer/contextBridge），且不含主进程特征。
/// 主进程入口是 package.json 的 main（.vite/build/index.pre.js），绝不能碰。
func isRendererPreload(_ data: Data) -> Bool {
    func has(_ s: String) -> Bool { data.range(of: Data(s.utf8)) != nil }
    let looksPreload = has("ipcRenderer") || has("contextBridge")
    let looksMain = has("app.whenReady") || has("new BrowserWindow") || has("app.on(")
    return looksPreload && !looksMain
}

/// asar 里的 preload 是否含注入标记。
func isPatched(_ t: AppTarget) -> Bool {
    guard FileManager.default.fileExists(atPath: t.asar.path),
          let data = (try? asarReadFile(t.asar, PRELOAD_REL)) ?? nil
    else { return false }
    return data.range(of: Data(MARKER.utf8)) != nil
}

/// 读原 asar，仅改 renderer 层文件，重打包到 outAsar。
/// 主进程文件（index.pre.js 及其 require 的 chunk）原样透传。
@discardableResult
func patchAsar(_ srcAsar: URL, _ outAsar: URL, _ css: String) throws -> [String] {
    let header = try asarReadHeader(srcAsar)
    let injection = Data(buildPreloadInjection(css).utf8)
    let style = Data("<style>/* \(MARKER) */ \(css)</style>".utf8)
    var patched: [String] = []
    var seen = Set<String>()

    let fh = try FileHandle(forReadingFrom: srcAsar)
    defer { try? fh.close() }

    try asarPack(header, outAsar) { sub, key in
        try fh.seek(toOffset: UInt64(header.base + key.0))
        let data = try fh.read(upToCount: key.1) ?? Data()
        if sub == PRELOAD_REL {
            if data.range(of: Data(MARKER.utf8)) != nil {
                throw CLIError("preload 已含 clfont 注入（应先还原）")
            }
            guard isRendererPreload(data) else {
                throw CLIError("\(PRELOAD_REL) 看起来不是 renderer preload"
                    + "（含主进程特征或缺少 ipcRenderer/contextBridge），为避免误伤主进程，中止。")
            }
            seen.insert(sub); patched.append(sub)
            return data + injection
        }
        if sub == HTML_REL, let r = data.range(of: Data("</head>".utf8)) {
            seen.insert(sub); patched.append(sub)
            var out = data
            out.replaceSubrange(r, with: style + Data("\n</head>".utf8))
            return out
        }
        return data
    }

    guard seen.contains(PRELOAD_REL) else {
        throw CLIError("未在 asar 中找到 preload \(PRELOAD_REL)（Claude 结构可能已变化），"
                     + "无法影响远程聊天页面，中止。")
    }
    return patched
}

/// 把 app 修回未打补丁状态（幂等，容忍任意半成品）：
/// 还原 asar → 同步 Info.plist 哈希 → 清理残留 → 按需重签 + 验证。
func restorePristine(_ t: AppTarget) throws {
    let fm = FileManager.default
    var changed = false
    for stale in [t.appDir, t.res.appendingPathComponent("app.clfont-tmp")] {
        if fm.fileExists(atPath: stale.path) {
            info("删除 \(stale.lastPathComponent)/（旧机制残留）")
            try? fm.removeItem(at: stale); changed = true
        }
    }
    for stale in [t.res.appendingPathComponent("app.asar.clfont-new"),
                  t.res.appendingPathComponent("app.asar.clfont-new.tmp")] {
        if fm.fileExists(atPath: stale.path) {
            info("删除 \(stale.lastPathComponent)")
            try? fm.removeItem(at: stale); changed = true
        }
    }
    if fm.fileExists(atPath: t.asarBak.path) {
        if !fm.fileExists(atPath: t.asar.path) || isPatched(t) {
            info("恢复 app.asar.bak → app.asar")
            _ = try? fm.removeItem(at: t.asar)
            try fm.copyItem(at: t.asarBak, to: t.asar)
        } else {
            info("app.asar 未含补丁（可能已被更新覆盖），保留之")
        }
        try? fm.removeItem(at: t.asarBak)
        changed = true
    }
    guard fm.fileExists(atPath: t.asar.path) else {
        throw CLIError("app.asar 与 app.asar.bak 均不存在，需从整包备份恢复")
    }
    let want = try asarHeaderHash(t.asar)
    if plistGetAsarHash(t) != want {
        info("同步 ElectronAsarIntegrity 哈希 → \(want.prefix(12))…")
        try plistSetAsarHash(t, want)
        changed = true
    }
    if changed || !Sign.valid(t) { try Sign.resign(t) }
    else { ok("签名验证通过（无需重签）") }
}
