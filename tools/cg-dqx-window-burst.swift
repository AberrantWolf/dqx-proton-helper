import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@_silgen_name("CGWindowListCreateImage")
func rawCGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage?

struct SeenKey: Hashable {
    let id: Int
    let sample: Int
}

let args = CommandLine.arguments
guard args.count == 4,
      let seconds = Double(args[1]),
      let interval = Double(args[2]) else {
    fputs("usage: cg-dqx-window-burst <seconds> <interval> <output-dir>\n", stderr)
    exit(2)
}

let outputDir = URL(fileURLWithPath: args[3], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let manifestURL = outputDir.appendingPathComponent("manifest.tsv")
FileManager.default.createFile(atPath: manifestURL.path, contents: nil)
guard let manifest = try? FileHandle(forWritingTo: manifestURL) else {
    fputs("failed to open manifest\n", stderr)
    exit(1)
}
defer { try? manifest.close() }

func writeManifest(_ line: String) {
    if let data = (line + "\n").data(using: .utf8) {
        try? manifest.write(contentsOf: data)
    }
}

func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    return nil
}

func shouldCapture(owner: String, title: String, width: Double, height: Double) -> Bool {
    let lowerOwner = owner.lowercased()
    if lowerOwner.contains("dqx") || lowerOwner.contains("wine") || lowerOwner.contains("crossover") {
        return true
    }
    if title.contains("ドラゴンクエスト") || title.contains("DQX") {
        return true
    }

    let hAndSSize = width >= 590 && width <= 670 && height >= 430 && height <= 510
    let bootSize = width >= 560 && width <= 760 && height >= 420 && height <= 650
    let launcherSize = width >= 650 && width <= 850 && height >= 550 && height <= 850
    return hAndSSize || bootSize || launcherSize
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let start = Date()
var sample = 0

writeManifest("elapsed\tsample\twindow_id\towner\ttitle\tx\ty\twidth\theight\tfile")
print("ready")
fflush(stdout)

while Date().timeIntervalSince(start) <= seconds {
    let elapsed = Date().timeIntervalSince(start)
    if let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for window in windows {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let title = window[kCGWindowName as String] as? String ?? ""
            guard let windowID = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }
            guard shouldCapture(owner: owner, title: title, width: width, height: height) else {
                continue
            }

            let filename = String(format: "win-%06.3f-s%04d-id%d-%0.fx%0.f.png",
                                  elapsed, sample, windowID, width, height)
            let outputURL = outputDir.appendingPathComponent(filename)
            if let image = rawCGWindowListCreateImage(.null, [.optionIncludingWindow],
                                                      CGWindowID(windowID), [.boundsIgnoreFraming]),
               writePNG(image, to: outputURL) {
                writeManifest(String(format: "%.6f\t%d\t%d\t%@\t%@\t%.0f\t%.0f\t%.0f\t%.0f\t%@",
                                     elapsed, sample, windowID, owner, title,
                                     x, y, width, height, filename))
            }
        }
    }
    sample += 1
    Thread.sleep(forTimeInterval: interval)
}
