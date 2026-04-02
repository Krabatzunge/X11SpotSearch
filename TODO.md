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
  - [ ] Category Search
- [ ] **Add default icons**: Add default icons for applications, with defaults for categories and overall default
- [x] **Make Window transparent**: add window transparency for rounded container
- [ ] **App Actions**: Use @ to search for app actions

## Fixes

- [x] **Skipping compositor solution**: skipping the compositor leads to glitchy windows on some systems -> find solution for heaving compositor, but getting compositor visual effects applied
- [ ] **Still glitchy even with compositor**
- [ ] **Fix Modifier Key duration**: Modifier keys like shift apply to long in the textinput still impacting up to two keys after modifier key release when typing faster
