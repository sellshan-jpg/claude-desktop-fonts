# Clfont

[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2026%2B-lightgrey)](#requirements)
[![Release](https://img.shields.io/github/v/release/sellshan-jpg/claude-desktop-fonts)](https://github.com/sellshan-jpg/claude-desktop-fonts/releases/latest)

[简体中文](README.md) | **English**

Clfont is a macOS tool that replaces the fonts in the Claude desktop app. Replace
Chinese characters only, Latin characters only, or both; anything you leave out —
and every interface icon — renders exactly as before.

> **Disclaimer**
>
> This is a third-party tool with no affiliation to Anthropic. The source is
> published so you can check what it does; it is licensed for non-commercial use
> only (see [License](#license)). Using it modifies the Claude.app installed on
> your Mac and replaces its code signature. Read
> [What re-signing costs you](#what-re-signing-costs-you) before you start.

## Contents

- [How it works](#how-it-works)
- [Safety](#safety)
- [Requirements](#requirements)
- [Installing](#installing)
- [Using it](#using-it)
- [What re-signing costs you](#what-re-signing-costs-you)
- [Known limits](#known-limits)
- [Reporting problems](#reporting-problems)
- [Tests](#tests)
- [Building from source](#building-from-source)
- [Command line](#command-line)
- [Repository layout](#repository-layout)
- [License](#license)

## How it works

The Claude desktop app renders its interface from the remote `claude.ai`, whose
text comes from two web font families: `anthropic-sans` and `anthropic-serif`.

Clfont appends a script to the renderer preload inside `app.asar`. That script
injects CSS of the following shape: it declares a font family of its own covering
only the code points being replaced, then puts that family at the front of
Claude's font variables.

```css
@font-face {
  font-family: ClaudeCJKSerif;          /* our own name, never one the page uses */
  src: local("STSongti-SC-Regular");
  unicode-range: U+4E00-9FFF, ...;      /* CJK code points only */
}
:root {
  --font-anthropic-serif: "ClaudeCJKSerif", "anthropic-serif", ui-serif, ... !important;
}
```

A font stack is resolved one character at a time: a character outside the first
family's `unicode-range` falls through to the next family in the stack. Covered
code points therefore use the font you chose, and everything else keeps rendering
in Claude's own web font. `unicode-range` is what defines the scope:

| Scope | Code points covered |
| --- | --- |
| Chinese | `U+2E80-2EFF`, `U+3000-303F`, `U+3400-4DBF`, `U+4E00-9FFF`, `U+F900-FAFF`, `U+FF00-FFEF` |
| English | `U+0020-007E` (Basic Latin); body text also gets `U+00C0-00FF` and `U+0100-017F` (accented Latin letters) |
| Both | All of the above |

The English scope **deliberately excludes the symbol range of Latin-1 Supplement
and the private use area**. Claude draws its interface icons as font glyphs, and
testing shows those glyphs live in exactly those ranges; leaving them out keeps
the icons intact when you replace English. Accented letters are opened up for the
body font only, never for the interface font that carries the icons.

**Never add a same-named `@font-face` to `anthropic-sans` or `anthropic-serif`.**
Those two families are loaded by the page over `url()`. Adding a declaration to
one makes Chromium rebuild the family, which puts the already-loaded web font
back into an unloaded state that it never recovers from — every Latin serif then
falls through the stack to `Georgia`. Measured: before the extra declaration the
family reads `loaded` and a digit string is 259.63px wide; after it, `unloaded`
and 251.97px, which is Georgia. It does not come back after fifteen seconds, nor
after an explicit `document.fonts.load()`. Replacement therefore always goes
through the variables, under family names the page does not use.

The face used for bold is chosen by measured stroke weight. Some fonts ship a
Bold too close to their regular — Songti lays down 1.16× the ink, Kaiti 1.23×,
where most fonts are past 1.34× — and a heavier face from the same family is used
in its place.

The defining property of this approach is that **no `font-family` declaration is
ever modified**. Claude's interface icons are font glyphs; replacing fonts by
overriding `font-family` would break them.

After `app.asar` changes, the `ElectronAsarIntegrity` hash in `Info.plist` has to
be updated and the app re-signed, or it will not launch.

## Safety

Everything Clfont does happens on your own Mac:

- **It checks the ground before it digs.** If something required is missing, it
  says so and stops, rather than leaving a half-modified app behind.
- **Only style rules are injected.** What reaches the page is CSS and nothing
  else: `@font-face` declarations, plus values for two kinds of custom property —
  font families and background colours. Its reach ends at glyph rendering for
  specific code points and the interface background. No network request is
  altered, no client identity is forged, and no limit, quota or billing is
  bypassed.
- **Your account and conversations are never touched.** Nothing about them is
  read or uploaded. The one outbound request is a read of this project's GitHub
  Releases endpoint (`api.github.com`) when checking for updates; it carries
  nothing about your machine, and the automatic check can be turned off under
  About.
- **Everything is undoable.** A full backup of the app is taken before anything
  changes. If a step fails or you cancel partway, the files go back to what they
  were and the signature is verified again. To bring back Anthropic's original
  signature along with the files, use Restore — which works fully whenever the
  backup matches the current version.

All of this is checkable in the source: the injected CSS is produced by
`build_css` in `clfont`, and `build_preload_injection` in the same file shows how
it gets written.

Worth stating plainly: this tool works by modifying an app bundle, which may not
sit well with Claude's terms of use. The author makes no warranty about any
consequence of using it. Whether to use it is your call.

## Requirements

| | |
| --- | --- |
| Processor | Apple Silicon |
| OS | macOS 26 or later |
| Dependencies | None |

Nothing extra is needed as of 6.0. The command-line half was rewritten from
Python to Swift and compiled into the app bundle; it shells out only to
`codesign`, `ditto`, `du` and `ps`, all four of which ship with the system. The
Xcode Command Line Tools, previously required, are not: the `python3` they
provide is a 118KB shim that cannot run without them.

## Installing

1. Download `Clfont.app` from
   [Releases](https://github.com/sellshan-jpg/claude-desktop-fonts/releases)
   and move it to your Applications folder.
2. The app is ad-hoc signed and not notarised by Apple, so Gatekeeper blocks the
   first launch. Clear the quarantine attribute:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Clfont.app
   ```

   Right-clicking the icon, choosing Open, and confirming in the dialog works
   just as well.

The interface comes in Simplified Chinese and English, following your system by
default, and can be switched by hand under About.

The first time you apply, macOS asks for the App Management permission — what it
takes to modify another app's bundle. Choose Allow. If you turned it down, Clfont
explains this in the window and offers a way straight to System Settings →
Privacy & Security → App Management; switch it on there and apply again.

On launch Clfont asks GitHub once, in the background, whether a newer version
exists — at most once a day, reading only the Releases endpoint, sending nothing
about your machine. You are told when there is one, and told nothing when the
check fails. It can be turned off under About.

## Using it

1. **Pick a target**, normally `/Applications/Claude.app`.
2. **Pick a scope and fonts.** Chinese replaces Chinese characters only and
   leaves the interface icons alone, which is why it is the recommendation.
   English and Both also change how the Latin text reads. Choose a font for each
   scope you turned on.
3. **Size.** Chinese and English each scale from 80% to 150%, which helps with
   fonts like Songti that come out small at their default size. It is implemented
   with `size-adjust` on `@font-face`, so it scales the replaced characters
   themselves and never touches a `font-size` value — interface icons, line
   spacing and layout are all unaffected.
4. **Compatibility.** Leave it on Standard. If some corner of the interface does
   not follow, switch to Extended, which applies the same rules across a wider set
   of font families.
5. **Apply.** It takes a minute or two.

Applying works through: quit the target app → take a full backup → repack
`app.asar` → update the integrity hash → re-sign → check that it launches. If any
step fails, or you cancel partway, the files go back to what they were and are
re-signed and verified, and Claude still starts normally.

One thing to know: **the automatic rollback restores the files, not the
signature.** The re-sign at the end is ad-hoc too, so the app does not return to
Anthropic's original signature. To get that back, use Restore — see
[Bringing back the original signature](#bringing-back-the-original-signature).

To undo everything, click Restore. If something looks wrong, click Diagnose:
Clfont checks app integrity, unfinished work, font availability, disk space,
hashes and signature state, and writes what it finds to the log.

## What re-signing costs you

**This is the part to understand before you start.**

Official Claude builds are signed by Anthropic (`TeamIdentifier=Q6L2SF6YDW`) with
hardened runtime enabled and a set of entitlements declared. Modifying `app.asar`
forces a re-sign, and this tool cannot get Anthropic's certificate, so the
signature it applies is ad-hoc. That has consequences:

- **`keychain-access-groups` is lost.** That entitlement covers the keychain
  access groups for WebAuthn passkeys and Microsoft workplace join. It is bound to
  a developer identity and cannot survive ad-hoc signing. If you sign in to Claude
  with a passkey or with Microsoft / Entra SSO, authentication may fail.
- **Hardened runtime is turned off**, lowering the app's security posture.
- **TCC permissions are forgotten.** The system records privacy permissions
  against a code signing identity, so microphone, notifications and the like have
  to be granted again once the signature changes.
- **The keychain asks again.** On the first launch after re-signing, macOS asks
  for the "Claude Safe Storage" item. The prompt can appear several times over
  (four, in testing); enter your login password and choose Always Allow each
  time. This is expected.

Every other entitlement is preserved in full. Only
`Contents/Resources/app.asar` and `Contents/Info.plist` are modified, and both are
sealed by the top-level signature — the signatures of Claude's internal
components (Helpers, Frameworks) are never broken, so only the top-level bundle
is re-signed. Before the first modification, the original entitlements of that
top level are recorded and written back on every subsequent signature. That is
how `com.apple.security.virtualization`, which Cowork and local virtual machines
need, survives.

> **Versions before 5.2** re-signed with `codesign --deep`, which re-signed
> Claude's internal components as well and cleared their entitlements, leaving
> Cowork and virtual machines unusable. If you used one of those, Clfont detects
> it after you upgrade and says so; applying once will restore from the full
> backup first and then modify, which brings the entitlements back. With no
> usable backup, reinstall Claude from <https://claude.ai/download>.

### Bringing back the original signature

Before its first modification Clfont takes a full backup of the app at
`~/.local/share/clfont/Claude-backup-<version>.app`. That backup is the original,
untouched build.

Restore is the only path back to the original signature. The automatic rollback
during a failed install does not use the backup — it puts the file contents back
and re-signs, and that signature is still ad-hoc. So if an install fails and you
want Claude completely untouched, run Restore afterwards.

When Restore finds a backup matching the current version, it puts the whole app
bundle back from it, and **Anthropic's original signature, hardened runtime and
every entitlement come back with it**. The `TeamIdentifier` is printed afterwards
so you can confirm.

If the backup does not match the current version — Claude auto-updated, say —
Restore can only put the file contents back and re-sign ad-hoc; the original
signature is gone. Reinstalling from <https://claude.ai/download> is the way out.
`clfont doctor` will tell you which situation you are in.

### Backup size and cleanup

At most two full backups are kept per target; anything beyond that is cleaned up
on the next install. Backups are made with `ditto`, which on the same APFS volume
means copy-on-write clones that cost almost nothing to create. Once Claude
updates, though, the blocks an old backup holds are no longer shared with
anything, and the space becomes real.

Expand Details on the status card to see what the current target's backups occupy
and to clear out old ones that can no longer restore anything. The backup matching
the current version is kept, since it is the only one that can bring back the
original signature. On the command line, use `clfont backups`; if you have used
this tool on more than one Claude, `clfont backups --all` lists and cleans up what
the other targets left behind.

## Known limits

- **A Claude update overwrites what was applied.** Clfont notices and says so in
  the main window, with a Re-apply button next to it. One click restores it, and
  nothing you chose has to be chosen again.
- **The implementation rides on Claude's current build.** The family names
  `anthropic-sans` and `anthropic-serif`, the variables
  `--font-anthropic-serif` / `--font-anthropic-sans`, the code font hook
  `--font-mono-override` and the background variables `--cds-surface-*` all come
  from the remote `claude.ai`; the bundle path `.vite/build/mainView.js`, the
  `ElectronAsarIntegrity` mechanism and the Electron fuse configuration come from
  the current desktop build. If any of those change, the modification may stop
  working until Clfont is updated.
- **CSS generic font keywords cannot be covered.** `system-ui`, `-apple-system`,
  `sans-serif` and friends are CSS keywords, and `@font-face` does not accept them
  as family names, so anywhere those stacks are used the Chinese keeps rendering
  in the system default. Claude's own stacks come through variables like
  `--font-anthropic-sans`, and this has not come up in testing.

## Reporting problems

If Claude itself starts misbehaving, put it back with Restore first, then judge
whether the problem has anything to do with this tool. Before filing a report
with Anthropic, make sure the app is not in a modified state.

Problems with Clfont are welcome at
[Issues](https://github.com/sellshan-jpg/claude-desktop-fonts/issues).

## Tests

```bash
python3 tests/test_clfont.py            # everything
python3 tests/test_clfont.py test_asar  # filter by name
UPDATE_GOLDEN=1 python3 tests/test_clfont.py   # refresh goldens after an intended change
```

```bash
CLFONT_BIN=build/clfont-swift python3 tests/test_clfont.py   # run against the Swift build
```

About 75 seconds, no third-party dependencies. The suite has two layers: the pure
layer calls functions in `clfont` directly, while the end-to-end layer runs real
commands against a fake Claude.app built by `tests/fixture.py`, covering install,
restore, idempotence, rollback from a failed smoke test, recovery from six crash
injection points, and the state markers the GUI depends on.

A real Claude.app is deliberately not used: one full backup is 800MB and about a
minute, and a test that breaks it breaks the app someone uses all day. The fake
app is 64KB and the whole flow finishes in seconds.

Three tests hold the two implementations to each other: the injected CSS is
byte-identical for the same configuration; repacking an asar unchanged reproduces
the original file byte for byte; and the full output of five subcommands matches
word for word once paths, hashes and timestamps are normalised. That last one
earns its place — the GUI parses state out of literal strings in that output, and
a difference in wording would not raise an error, it would just leave the
interface showing the wrong state indefinitely.

## Building from source

```bash
./gui/build.sh                  # produces build/Clfont.app, CLI included
./cli/build.sh                  # CLI only, produces build/clfont-swift
```

Building needs `swiftc` and `iconutil` from Xcode. The interface uses the Liquid
Glass API from macOS 26, so the compile target is `arm64-apple-macos26.0`.

## Command line

The command-line tool stands on its own:

```bash
clfont install --mode auto                 # apply
clfont install --scope both --scale 120 --scale-latin 90   # scope and size
clfont status                              # current state
clfont doctor                              # check the environment
clfont uninstall                           # restore
clfont backups                             # list full backups and what they cost
clfont backups --prune                     # clear backups that can no longer restore
clfont backups --all                       # include other targets' backups
clfont --app /path/to/Claude.app install   # target a Claude installed elsewhere
```

## Repository layout

| Path | What it is |
| --- | --- |
| `cli/` | The command-line tool, in Swift, compiled into the app bundle. Every file operation happens here |
| `clfont` | The same tool in Python. **Not used at runtime**; kept as the reference the regression tests compare against |
| `tests/` | Regression tests. One set of assertions, run against both implementations, whose output must match word for word |
| `gui/ClfontApp.swift` | The SwiftUI interface. It only calls the command-line tool; it never touches the target app itself |
| `gui/render-icon.swift` | Draws the app icon; called by the build script |
| `gui/build.sh` | Build script: compile, generate the icon, assemble the bundle, sign |

## License

Copyright © 2026 赵万 (Jovan). This project is licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE). It is source-available, not open
source. In short:

- **Free for personal and non-commercial use**, including personal study,
  research and your own daily use.
- **No commercial use of any kind**, including but not limited to distribution
  for a fee, bundling into a paid product, or use in the business activities of a
  for-profit organisation.
- You may read, modify and redistribute it, but **the licence and the copyright
  notice must be kept**, and redistribution carries the same non-commercial
  restriction.

The licence text governs. For a commercial licence, get in touch through
[Issues](https://github.com/sellshan-jpg/claude-desktop-fonts/issues).
