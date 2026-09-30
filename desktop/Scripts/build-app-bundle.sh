#!/bin/bash
# Wraps the already-built `swift build -c release` executable in a real
# .app bundle (Contents/MacOS + Contents/Info.plist), instead of running
# the bare Mach-O binary directly the way the launcher did before.
#
# Real, live-reported problem this investigates (2026-08-29): the app
# crashes on a mic-button click with a SIGABRT entirely inside SwiftUI's
# own Button-gesture dispatch (`_ButtonGesture.internalBody.getter` ->
# `MainActor.assumeIsolated`), on macOS 26.6.2. Two earlier fix attempts
# (rewriting the audio-tap code itself, then removing an unrelated
# `arch -arm64` wrapper from the launcher) did not resolve it — the same
# byte-identical crash signature recurred both times. This is the next
# real, different lead: this app has never run as a genuine .app bundle.
# `Sources/VoiceLedgerApp/Info.plist` is linker-embedded directly into the
# Mach-O binary (`-sectcreate __TEXT __info_plist`) specifically because
# there was no real bundle to put a Contents/Info.plist in — an unusual
# setup that could plausibly cause AppKit's gesture/event routing (which
# assumes normal bundle-based app initialization) to behave differently
# than it would for a properly bundled app. Not yet confirmed as the
# actual cause — this is a real, reasoned attempt, not a guaranteed fix.
#
# Usage: scripts/build-app-bundle.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
# Regression gate (2026-09-30): a release bundle never ships numbers that
# silently changed. Skip only deliberately: VL_SKIP_PREFLIGHT=1 (e.g. when
# the backend is down) — the skip is printed so it can't go unnoticed.
if [ "$CONFIG" = "release" ]; then
  if [ "${VL_SKIP_PREFLIGHT:-0}" = "1" ]; then
    echo "build-app-bundle: PREFLIGHT SKIPPED (VL_SKIP_PREFLIGHT=1)"
  else
    "$(dirname "$0")/preflight.sh" --skip-tests || { echo "build-app-bundle: preflight failed — not bundling"; exit 1; }
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$DESKTOP_DIR/.build/$CONFIG/VoiceLedgerApp"
APP_BUNDLE="$DESKTOP_DIR/.build/$CONFIG/VoiceLedgerApp.app"

if [ ! -x "$BINARY" ]; then
    echo "error: $BINARY does not exist — run 'swift build -c $CONFIG' first." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/VoiceLedgerApp"

# Interactive chart assets (local only — no CDN): ECharts, the shared option
# builders also used by the PDF renderer, and the chart host page.
RENDERER_DIR="$(cd "$(dirname "$0")/../../report-renderer" 2>/dev/null && pwd)"
if [ -n "$RENDERER_DIR" ] && [ -f "$RENDERER_DIR/node_modules/echarts/dist/echarts.min.js" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Charts"
    cp "$RENDERER_DIR/app-host/chart-host.html" "$RENDERER_DIR/shared/vl-charts.js" "$RENDERER_DIR/node_modules/echarts/dist/echarts.min.js" "$APP_BUNDLE/Contents/Resources/Charts/"
else
    echo "warning: report-renderer/node_modules missing — run 'npm install' in report-renderer for in-app charts." >&2
fi

# The PDF renderer runs outside ~/Documents so the app never needs macOS's
# Documents-folder permission (which re-prompts after every rebuild).
if [ -n "$RENDERER_DIR" ] && [ -x "$RENDERER_DIR/.venv/bin/python" ]; then
    RUNTIME_DIR="$HOME/Library/Application Support/VoiceLedger/Renderer"
    mkdir -p "$RUNTIME_DIR"
    rsync -a --delete --exclude samples --exclude test --exclude '__pycache__' "$RENDERER_DIR/" "$RUNTIME_DIR/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.voiceledger.app</string>
	<key>CFBundleName</key>
	<string>Voice Ledger</string>
	<key>CFBundleDisplayName</key>
	<string>Voice Ledger</string>
	<key>CFBundleExecutable</key>
	<string>VoiceLedgerApp</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Voice Ledger uses your microphone for voice commands — navigating pages, reviewing findings, and asking questions about what's flagged. Voice never applies a QuickBooks write on its own; every write still requires a real on-screen confirmation.</string>
	<!-- Root cause of the "sometimes launches with zero windows" flakiness
	     (2026-08-29, confirmed live across multiple launches, both before
	     and after switching to `open -a`): macOS persists how many windows
	     were open at the last quit and replays that on the next launch by
	     default (NSQuitAlwaysKeepsWindows defaults to true). Any quit that
	     happened with 0 windows open (this app's one WindowGroup window
	     closed, or the AppDelegate reopen fix never got a chance to run)
	     got "restored" as 0 windows on the very next launch, regardless of
	     the AppDelegate's own reopen handling — that handling only helps
	     once a window has existed in the CURRENT process; it can't run
	     before SwiftUI's first window would otherwise appear. Setting this
	     false makes every launch create its default window fresh, the way
	     a normal single-window utility app behaves, rather than depending
	     on whatever state the previous quit happened to leave behind. -->
	<key>NSQuitAlwaysKeepsWindows</key>
	<false/>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign the whole bundle (not just the raw Mach-O, which macOS
# auto-signs ad-hoc on its own) — a real .app is expected to carry one
# consistent signature over the bundle as a unit.
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1

echo "Built $APP_BUNDLE"
