# Desktop Bins Widget

A macOS menu bar app that puts widget-style panels on the desktop. Each
panel is a titled, resizable container that holds files and folders you drag
into it, laid out on its own icon grid.

Companion to — and a different product from — Desktop Bins. That app
arranges Finder's real desktop icons; this one owns its contents.

## Why not a WidgetKit widget

A literal WidgetKit desktop widget cannot do this. Widgets run in a
sandboxed extension: they cannot send Apple Events, cannot be a drag-and-drop
destination, come only in fixed system sizes placed from the widget gallery,
and are limited to buttons and toggles for interaction. A widget could
*display* a bin's contents, but never hold, accept or arrange them.

These panels are therefore ordinary app windows pinned to the desktop
layer — widget-like in feel, fully interactive in practice.

## Features

- Panels holding files and folders, dragged in from anywhere
- Drag to reorder within a panel; drop indicator shows where an item will land
- Double-click an item to open it; right-click to reveal in Finder or remove
- Drag by the title bar, resize from the corner, double-click the title to collapse
- Rename, recolor and delete panels
- Icon size, panel opacity and labels are configurable
- Panels remember which physical monitor they belong to, and appear on the
  main display rather than vanishing when that monitor is absent
- "Bring All Bins to Main Display" rescues panels stranded on a monitor that
  is no longer attached
- Desktop icons of items in a bin are hidden, so the same file isn't shown twice
- Each set of monitors remembers its own arrangement
- Item count in the title bar can be turned off per bin
- Optional Command-drag to move, so bins can't be nudged by accident
- Updates itself from the menu bar, verifying the download before installing
- Optional launch at login

## Installing

Download the `.dmg` from the [latest release](https://github.com/smanke/Desktop-Bins-Widget/releases),
open it, and drag the app onto Applications. The image and the app inside are
both notarized, so it opens without a Gatekeeper warning.

## Building

```bash
./build_app.sh
cp -R ".build/app/Desktop Bins Widget.app" /Applications/
open "/Applications/Desktop Bins Widget.app"
```

Requires macOS 13+. Signs with a Developer ID identity when one is present
(see `build_app.sh`), which keeps the app's identity stable across rebuilds.
`./notarize.sh` submits and staples a build for sharing to other Macs, and
`./make_dmg.sh` packages the stapled app into a signed, notarized `.dmg`
with the usual drag-to-Applications layout.

## Implementation notes

### No Finder dependency

This is the significant departure from Desktop Bins. Because a panel owns
its items, the app never sends an Apple Event, so there is no Automation
permission, no TCC prompt, and none of the silent-failure modes that come
with driving Finder. It also means each panel is a single ordinary window
rather than the three-window arrangement Desktop Bins needs to stay both
visible behind desktop icons and clickable.

Panels sit at `desktopIconWindow + 1`: above the desktop so they receive
clicks, below every ordinary window so they never cover real work.

### Item references

Items store a bookmark alongside the path, so a shortcut keeps working when
its file is moved or renamed. The path is the fallback when a bookmark can't
be resolved. Items whose file no longer exists are drawn dimmed, and
"Remove Missing Items" in the menu clears them.

Layout follows list order, so panels are inherently gap-free — there is no
grid snapping to configure, unlike Desktop Bins.

### Hiding desktop icons

An item dropped in from the Desktop would otherwise appear twice — once in
the bin and once loose on the desktop — so the file is marked hidden and
Finder stops drawing it. Nothing is moved or renamed, so it is undone by
clearing the flag: removing the item from a bin, deleting the bin, or turning
the setting off all restore it, and "Show All Hidden Desktop Icons" in the
menu is the catch-all.

Only files sitting directly on the Desktop are touched. Hiding something
dragged in from Documents would make it vanish from a folder the user is
actively browsing, which is not what "hide the desktop icon" means.

### Updating

"Check for Updates…" reads the latest GitHub release, downloads its disk
image, and replaces the running app.

Since that installs code fetched from the network, nothing is trusted on the
strength of where it came from. Before anything is copied over the installed
app, the downloaded bundle must pass `codesign --verify --deep --strict`,
carry the **same Team ID as the app that is running** (so a valid signature
belonging to someone else is refused), and pass Gatekeeper assessment, which
only succeeds if Apple notarized it. Any failure aborts and leaves the
installed app untouched.

The swap itself is handed to a detached shell script, because an app cannot
replace and relaunch its own bundle while it is the one running: the script
waits for the process to exit, replaces the bundle, and reopens it.

### Multiple displays

Each panel stores the stable UUID of its display
(`CGDisplayCreateUUIDFromDisplayID`) plus its offset within that display,
never a raw `CGDirectDisplayID` — those are assigned per session, so the
same monitor can return with a different id. Storing an offset rather than
an absolute point keeps panels in place when displays are rearranged and the
global coordinate space shifts. A panel whose display is not attached is shown on the main display instead of
being hidden — plugging a laptop into a different set of monitors should not
look like the panels were lost. Its stored pin is left untouched so it
returns home when its own monitor comes back; it is only re-pinned if the
user actually moves it. Offsets from a larger monitor are clamped into the
fallback screen so a panel can't land off-screen. "Bring All Bins to Main
Display" in the menu tiles everything onto the main display as an emergency
recovery.

Each panel also remembers a separate arrangement per monitor setup, keyed by
a signature of the attached displays. Moving between a desk, a second desk
and the bare laptop restores whatever layout was last used with each, rather
than keeping a single position that the previous setup overwrites.
