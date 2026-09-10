# UI design — 0.2

## Direction

A quiet native Mac utility: the current account, remaining quota and next action should be readable at a glance. Account management uses a sidebar; everyday switching happens inside the menu-bar panel. System materials, controls, SF typography and semantic colors adapt to macOS appearance.

The original identity is a pair of rounded exchange arrows on a cobalt plate. White and ice-blue arrows remain recognizable at small sizes. The icon is generated from editable AppKit vector geometry at exact 1× and 2× pixel dimensions; the menu-bar template uses the same motif. No upstream artwork or third-party icon assets are included.

## Interaction decisions

- Current credentials appear first. Search covers all accounts, and filtering updates the detail selection.
- Quota cards distinguish window duration, remaining percentage and reset time. Unknown values stay unknown; stale or failed reads keep a visible cache indicator.
- The main window and menu panel share a confirmation view that names the source and destination. A pause-task checkbox precedes the action.
- Pending verification stays prominent, with confirmation and recovery actions. A replaced credential file is never described as verified desktop login.
- Email visibility defaults to hidden; nicknames remain visible. Appearance and visibility preferences persist locally. Public visuals use synthetic demo accounts only.

## References and provenance

Design work used the frontend-design skill for critique and visual hierarchy. Reference patterns were studied, not copied:

- [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/): a simple recognizable concept and clarity at small sizes.
- [Apple Icons](https://developer.apple.com/design/human-interface-guidelines/icons): consistent, understandable symbols.
- [SwiftUI MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra): native menu-bar utility presentation.
- [Raycast Action Panel](https://manual.raycast.com/action-panel): actions close to the selected item.
- [Raycast Keyboard Shortcuts](https://manual.raycast.com/keyboard-shortcuts): discoverable, repeatable keyboard actions.

The flattened `.icns` supports the existing macOS 14+ build path without requiring Icon Composer or a paid developer account. It is not a layered Liquid Glass icon. Platform-specific layered assets can be evaluated separately.

## Review

See [validation](VALIDATION.md) for checked states and the remaining real-account acceptance boundary. The icon review board is rendered entirely from original drawing code and contains no account, device or workspace information.

## 0.2.1 quota naming

Use the optional `limitName` from the [official rate-limit response](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt). Empty names, names identical to the raw ID, and machine-style underscore labels fall back to an unidentified group; do not guess a model from its code name. Show recognized Codex first, keep unknown pools in a collapsed disclosure, and expose IDs only in the information popover. Summaries use the tightest Codex window, never an unrelated full pool. Old cache IDs and period labels are projected without a destructive migration.
