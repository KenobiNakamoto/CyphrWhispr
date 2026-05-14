// Tiny helper: locate CyphrWhispr's Settings window on screen and print
// its CG bounds (top-left origin, multi-display safe). Output:
//
//   FRAME <x> <y> <w> <h>
//
// or "NOT_FOUND" if no matching window is currently visible.
//
// Used by scripts/dev-screenshot.sh to feed `screencapture -R`. Querying
// CGWindowListCopyWindowInfo here lets us avoid manual y-axis flipping
// of NSWindow's bottom-left coordinates, which is fragile on multi-screen
// setups where the user has displays stacked vertically.

import AppKit

let opts: CGWindowListOption = [.optionOnScreenOnly]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    print("NOT_FOUND"); exit(1)
}

for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let title = window[kCGWindowName as String] as? String ?? ""
    // Match by owner = "CyphrWhispr" AND title containing "Settings".
    // Title-only match isn't enough — System Settings is also "Settings".
    guard owner == "CyphrWhispr",
          title.contains("Settings"),
          let b = window[kCGWindowBounds as String] as? [String: CGFloat],
          let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
    else { continue }
    print("FRAME \(Int(x)) \(Int(y)) \(Int(w)) \(Int(h))")
    exit(0)
}
print("NOT_FOUND")
exit(2)
