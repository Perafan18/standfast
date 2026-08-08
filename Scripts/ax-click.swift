// A real click, because `AXPress` is not one.
//
// On macOS 27 `perform action "AXPress"` on a SwiftUI `MenuBarExtra` menu item
// marks the element selected in the Accessibility tree without ever running the
// item's action: no window opens and the app's own scene-activation logger never
// fires, so the press is lost before it reaches SwiftUI. Menu tracking only
// starts for genuine HID events, so the lifecycle probe posts those instead.
//
// This is a probe-only tool. Nothing in the shipping app depends on it.

import CoreGraphics
import Foundation

private func failUsage() -> Never {
  FileHandle.standardError.write(
    Data("usage: ax-click <x> <y> | ax-click move <x> <y> | ax-click where\n".utf8))
  exit(2)
}

private func currentLocation() -> CGPoint? {
  CGEvent(source: nil)?.location
}

private func post(_ type: CGEventType, at point: CGPoint) -> Bool {
  guard
    let event = CGEvent(
      mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
      mouseButton: .left)
  else { return false }
  event.post(tap: .cghidEventTap)
  return true
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["where"] {
  guard let location = currentLocation() else {
    FileHandle.standardError.write(Data("cannot read the pointer location\n".utf8))
    exit(1)
  }
  print("\(Int(location.x.rounded())) \(Int(location.y.rounded()))")
  exit(0)
}

let moveOnly = arguments.first == "move"
let coordinates = moveOnly ? Array(arguments.dropFirst()) : arguments

guard coordinates.count == 2, let x = Double(coordinates[0]),
  let y = Double(coordinates[1])
else { failUsage() }

let target = CGPoint(x: x, y: y)

if moveOnly {
  guard post(.mouseMoved, at: target) else {
    FileHandle.standardError.write(Data("cannot post a pointer move\n".utf8))
    exit(1)
  }
  exit(0)
}

// Move first and let the window server settle: a down event delivered in the
// same breath as the move can be attributed to the previous location, which
// silently clicks whatever the pointer was over before.
guard post(.mouseMoved, at: target) else {
  FileHandle.standardError.write(Data("cannot post a pointer move\n".utf8))
  exit(1)
}
usleep(120_000)

guard post(.leftMouseDown, at: target), post(.leftMouseUp, at: target) else {
  FileHandle.standardError.write(Data("cannot post a click\n".utf8))
  exit(1)
}
