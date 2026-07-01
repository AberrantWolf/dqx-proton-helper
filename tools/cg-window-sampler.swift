import CoreGraphics
import Foundation

let args = CommandLine.arguments
let seconds = args.count > 1 ? (Double(args[1]) ?? 5.0) : 5.0
let interval = args.count > 2 ? (Double(args[2]) ?? 0.05) : 0.05
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let start = Date()

func maybePrintWindow(_ window: [String: Any], sample: Int, elapsed: TimeInterval) {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let title = window[kCGWindowName as String] as? String ?? ""
    let windowID = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let alpha = window[kCGWindowAlpha as String] as? Double ?? -1
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Double,
          let y = bounds["Y"] as? Double,
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return
    }

    let ownerMatch = owner.lowercased().contains("dqx") ||
                     owner.lowercased().contains("wine") ||
                     owner.lowercased().contains("crossover")
    let titleMatch = title.contains("ドラゴンクエスト") || title.contains("DQX")
    let hAndSSize = width >= 590 && width <= 660 && height >= 440 && height <= 500
    let bootSize = width >= 600 && width <= 650 && height >= 580 && height <= 610
    let launcherSize = width >= 650 && width <= 850 && height >= 650 && height <= 850

    if ownerMatch || titleMatch || hAndSSize || bootSize || launcherSize {
        print(String(format: "t=%.3f sample=%03d id=%d owner=%@ title=%@ layer=%d alpha=%.2f bounds=(%.0f,%.0f %.0fx%.0f)",
                     elapsed, sample, windowID, owner, title, layer, alpha, x, y, width, height))
    }
}

var sample = 0
while Date().timeIntervalSince(start) <= seconds {
    let elapsed = Date().timeIntervalSince(start)
    if let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for window in windows {
            maybePrintWindow(window, sample: sample, elapsed: elapsed)
        }
    }
    fflush(stdout)
    sample += 1
    Thread.sleep(forTimeInterval: interval)
}
