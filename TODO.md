## Features

- [x] **Cursor blinking**: timerfd + poll() alongside XCB fd
- [ ] **Smooth resize animation**: frame timer for animated height changes
- [ ] **Scrolling**: Arrow keys past max_results scrolls the full list
- [ ] **Clipboard / text selection**: Ctrl + A/C/V via XCB selections
- [ ] **Multi-monitor**: xcb-randr to center on active output
- [ ] **Wayland support**: wlr-layer-shell
- [ ] **Config file**: Colors, fonts, hotkey, max results from file
- [ ] **Widgets**: Use "$" to search for widgets -> widgets can also appear in normal search as attachment after the last result item
  - [ ] Time Widget
  - [ ] Math Widget
  - [ ] Weather
  - [ ] Date
- [ ] **Specify search**: \#name for only searching with names, \#category for categories, etc.
  - [x] Name Search
  - [x] Description Search
  - [ ] Category Search (best thing is to have category search where you select categories and then have a search within this category for apps -> more complicated skip for now)
- [x] **Add default icons**: Add default icons for applications, with defaults for categories and overall default
  - [x] Default icon
  - [x] Default category icons (Desktop entry already supports categories)
- [x] **Make Window transparent**: add window transparency for rounded container
- [ ] **App Actions**: Use @ to search for app actions

## Improvements

- [x] **Icon Cache hit** Desktop files without icons are constantly triggering research (expensive) as the cache is on the default application icon instead of their application name
- [x] **Add X- Category parsing**: parse for X- categories to add custom category support

## Fixes

- [x] **Skipping compositor solution**: skipping the compositor leads to glitchy windows on some systems -> find solution for heaving compositor, but getting compositor visual effects applied
- [x] **Still glitchy even with compositor**
- [x] **Fix Modifier Key duration**: Modifier keys like shift apply to long in the textinput still impacting up to two keys after modifier key release when typing faster
