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

guard CommandLine.arguments.count == 3,
      let windowIDValue = UInt32(CommandLine.arguments[1]) else {
    fputs("usage: cg-window-capture <window-id> <output.png>\n", stderr)
    exit(2)
}

let windowID = CGWindowID(windowIDValue)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = rawCGWindowListCreateImage(.null, [.optionIncludingWindow], windowID, [.boundsIgnoreFraming]) else {
    fputs("failed to create image for window \(windowID)\n", stderr)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("failed to create png destination\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, image, nil)
if !CGImageDestinationFinalize(destination) {
    fputs("failed to write png\n", stderr)
    exit(1)
}
