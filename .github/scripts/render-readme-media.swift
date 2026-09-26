import AppKit
import CoreGraphics
import Foundation

struct MediaError: Error, CustomStringConvertible {
    let description: String
}

func color(_ hex: String) -> NSColor {
    let value = UInt32(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x334155
    return NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: 1
    )
}

func savePNG(_ path: String, width: Int, height: Int, draw: () throws -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw MediaError(description: "Could not create bitmap context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    try draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw MediaError(description: "Could not encode PNG")
    }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func drawCover(_ path: String, in rect: CGRect) throws {
    guard let image = NSImage(contentsOfFile: path),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw MediaError(description: "Could not open image: \(path)")
    }
    let sourceWidth = CGFloat(source.width)
    let sourceHeight = CGFloat(source.height)
    let sourceRatio = sourceWidth / sourceHeight
    let targetRatio = rect.width / rect.height
    var crop = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
    if sourceRatio > targetRatio {
        crop.size.width = sourceHeight * targetRatio
        crop.origin.x = (sourceWidth - crop.width) / 2
    } else {
        crop.size.height = sourceWidth / targetRatio
        crop.origin.y = (sourceHeight - crop.height) / 2
    }
    guard let cropped = source.cropping(to: crop.integral) else {
        throw MediaError(description: "Could not crop image: \(path)")
    }
    NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)).draw(in: rect)
}

func drawImage(_ path: String, in rect: CGRect) throws {
    guard let image = NSImage(contentsOfFile: path) else {
        throw MediaError(description: "Could not open image: \(path)")
    }
    image.draw(in: rect)
}

func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
}

func gradient(_ rect: CGRect, _ top: String, _ bottom: String) {
    NSGradient(starting: color(top), ending: color(bottom))?.draw(in: rect, angle: 90)
}

func makeWallpaper(_ output: String) throws {
    try savePNG(output, width: 1600, height: 1000) {
        gradient(CGRect(x: 0, y: 0, width: 1600, height: 1000), "53677A", "263447")
        let glow = NSBezierPath(ovalIn: CGRect(x: 840, y: 430, width: 900, height: 740))
        NSColor.white.withAlphaComponent(0.055).setFill()
        glow.fill()
    }
}

func makeSocialPreview(_ output: String, _ iconPath: String, _ appName: String, _ tagline: String, _ screenshotPath: String) throws {
    let accents: [String: (String, String)] = [
        "Clipboard Shelf": ("176F64", "173A45"),
        "Quick Drop Zone": ("4B83E8", "292F83"),
        "EchoType": ("18364E", "101B34"),
        "CaptionGrab": ("168FE7", "1651B4")
    ]
    let pair = accents[appName] ?? ("416B95", "202B44")
    guard !screenshotPath.isEmpty,
          FileManager.default.fileExists(atPath: screenshotPath),
          let screenshot = NSImage(contentsOfFile: screenshotPath),
          screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
        throw MediaError(description: "Social preview requires a readable real app screenshot")
    }
    try savePNG(output, width: 1280, height: 640) {
        gradient(CGRect(x: 0, y: 0, width: 1280, height: 640), pair.0, pair.1)
        let panel = CGRect(x: 690, y: 52, width: 530, height: 536)
        let panelPath = NSBezierPath(roundedRect: panel, xRadius: 26, yRadius: 26)
        NSColor.black.withAlphaComponent(0.20).setFill()
        panelPath.fill()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        try drawCover(screenshotPath, in: panel.insetBy(dx: 10, dy: 10))
        NSGraphicsContext.restoreGraphicsState()
        try drawImage(iconPath, in: CGRect(x: 82, y: 398, width: 132, height: 132))
        drawText(appName, in: CGRect(x: 82, y: 290, width: 570, height: 78), size: 50, weight: .bold, color: .white)
        drawText(tagline, in: CGRect(x: 84, y: 175, width: 550, height: 104), size: 24, weight: .regular, color: NSColor.white.withAlphaComponent(0.93))
        drawText("A native app for macOS", in: CGRect(x: 84, y: 82, width: 450, height: 34), size: 17, weight: .medium, color: NSColor.white.withAlphaComponent(0.77))
    }
}

func makeBanner(_ output: String, _ iconPaths: [String]) throws {
    guard iconPaths.count == 4 else { throw MediaError(description: "Banner needs exactly four icons") }
    try savePNG(output, width: 1280, height: 320) {
        gradient(CGRect(x: 0, y: 0, width: 1280, height: 320), "647487", "3B4B60")
        drawText("Small tools for macOS", in: CGRect(x: 72, y: 115, width: 510, height: 70), size: 42, weight: .bold, color: .white)
        for (index, path) in iconPaths.enumerated() {
            try drawImage(path, in: CGRect(x: 610 + index * 150, y: 94, width: 120, height: 120))
        }
    }
}

func makeProfileSocial(_ output: String, _ iconPaths: [String]) throws {
    guard iconPaths.count == 4 else { throw MediaError(description: "Profile social preview needs exactly four icons") }
    try savePNG(output, width: 1280, height: 640) {
        gradient(CGRect(x: 0, y: 0, width: 1280, height: 640), "53677A", "263447")
        drawText("9phfr6dsw4-dotcom", in: CGRect(x: 78, y: 386, width: 650, height: 76), size: 46, weight: .bold, color: .white)
        drawText("Small, thoughtful tools for macOS.", in: CGRect(x: 82, y: 292, width: 620, height: 54), size: 28, weight: .medium, color: NSColor.white.withAlphaComponent(0.94))
        drawText("Clipboard history · file organization · dictation · captions", in: CGRect(x: 82, y: 220, width: 650, height: 48), size: 19, weight: .regular, color: NSColor.white.withAlphaComponent(0.78))
        for (index, path) in iconPaths.enumerated() {
            let tile = CGRect(x: 806 + (index % 2) * 176, y: 368 - (index / 2) * 174, width: 136, height: 136)
            let tilePath = NSBezierPath(roundedRect: tile, xRadius: 24, yRadius: 24)
            NSColor.white.withAlphaComponent(0.08).setFill()
            tilePath.fill()
            try drawImage(path, in: tile.insetBy(dx: 8, dy: 8))
        }
    }
}

func seedClipboard() throws {
    struct Entry: Encodable {
        let id: UUID
        let text: String
        let isPinned: Bool
        let createdAt: Date
    }
    let now = Date()
    let entries = [
        Entry(id: UUID(), text: "func normalize(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }", isPinned: true, createdAt: now.addingTimeInterval(-300)),
        Entry(id: UUID(), text: "https://swift.org/documentation/", isPinned: true, createdAt: now.addingTimeInterval(-900)),
        Entry(id: UUID(), text: "Planning notes — outline, first draft, review, final copy", isPinned: false, createdAt: now.addingTimeInterval(-1500)),
        Entry(id: UUID(), text: "Build succeeded on macOS 26 · checks ready", isPinned: false, createdAt: now.addingTimeInterval(-2100)),
        Entry(id: UUID(), text: "Release checklist: tests, package, checksum, publish", isPinned: false, createdAt: now.addingTimeInterval(-2700)),
        Entry(id: UUID(), text: "Meet at the north entrance at 10:30", isPinned: false, createdAt: now.addingTimeInterval(-3300)),
        Entry(id: UUID(), text: "🌿 Small steps, clear notes, and a little patience.", isPinned: false, createdAt: now.addingTimeInterval(-3900)),
        Entry(id: UUID(), text: "git status --short", isPinned: false, createdAt: now.addingTimeInterval(-4500))
    ]
    let data = try JSONEncoder().encode(entries)
    let domain = "local.clipboardshelf" as CFString
    CFPreferencesSetAppValue("ClipboardShelfHistoryV1" as CFString, data as CFPropertyList, domain)
    CFPreferencesSetAppValue("ClipboardShelfRecordingPausedV1" as CFString, false as CFPropertyList, domain)
    guard CFPreferencesAppSynchronize(domain) else {
        throw MediaError(description: "Could not synchronize synthetic clipboard history")
    }
}

func seedEchoType() throws {
    struct Record: Encodable {
        let id: UUID
        let text: String
        let timestamp: Date
        let duration: TimeInterval
        let modelID: String
    }
    let now = Date()
    let records = [
        Record(id: UUID(), text: "The clearest plans begin with one small step. Write down the goal, decide what matters today, and leave room to adjust as new information arrives.", timestamp: now.addingTimeInterval(-900), duration: 18.2, modelID: "apple-speech"),
        Record(id: UUID(), text: "A useful note captures the idea while it is fresh. The first draft does not need to be perfect; it only needs to make the next action clear.", timestamp: now.addingTimeInterval(-2400), duration: 17.4, modelID: "apple-speech"),
        Record(id: UUID(), text: "For a calm review, check the title, confirm each link, and read the instructions once from beginning to end. Small edits are easier when the structure is already sound.", timestamp: now.addingTimeInterval(-86_400 - 1800), duration: 19.1, modelID: "apple-speech"),
        Record(id: UUID(), text: "A good workspace keeps related material together and leaves temporary items easy to clear. Keep the names simple so the next person can find what they need.", timestamp: now.addingTimeInterval(-2 * 86_400 - 2400), duration: 18.8, modelID: "apple-speech"),
        Record(id: UUID(), text: "Before sharing a release, run the tests, inspect the packaged application, and verify the download checksum. Then publish the exact build that passed those checks.", timestamp: now.addingTimeInterval(-3 * 86_400 - 2100), duration: 19.5, modelID: "apple-speech")
    ]
    let historyDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/EchoTypeTranscriptHistory", isDirectory: true)
    try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
    let destination = historyDirectory.appendingPathComponent("transcripts.json")
    try JSONEncoder().encode(records).write(to: destination, options: .atomic)
}

func printWindow(_ owner: String) throws {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let rows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        throw MediaError(description: "Could not enumerate on-screen windows")
    }
    let candidates: [(CGWindowID, CGRect)] = rows.compactMap { row in
        guard (row[kCGWindowOwnerName as String] as? String) == owner,
              (row[kCGWindowLayer as String] as? Int ?? 99) == 0,
              (row[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              let id = row[kCGWindowNumber as String] as? CGWindowID,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue,
              width >= 280, height >= 180 else { return nil }
        return (id, CGRect(x: x, y: y, width: width, height: height))
    }
    guard let best = candidates.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else {
        throw MediaError(description: "No visible window found for \(owner)")
    }
    let r = best.1
    let scale = displayScale(CGMainDisplayID())
    print("\(best.0)|\(Int(r.minX))|\(Int(r.minY))|\(Int(r.width))|\(Int(r.height))|\(scale)")
}

func printVisibleWindows() throws {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let rows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        throw MediaError(description: "Could not enumerate on-screen windows")
    }
    for row in rows {
        guard let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
        let owner = (row[kCGWindowOwnerName as String] as? String ?? "unknown").replacingOccurrences(of: "|", with: " ")
        let name = (row[kCGWindowName as String] as? String ?? "").replacingOccurrences(of: "|", with: " ")
        let layer = row[kCGWindowLayer as String] as? Int ?? -1
        let alpha = row[kCGWindowAlpha as String] as? Double ?? 0
        print("\(owner)|\(name)|\(Int(x))|\(Int(y))|\(Int(width))|\(Int(height))|layer=\(layer)|alpha=\(alpha)")
    }
}

func displayScale(_ display: CGDirectDisplayID) -> Int {
    let bounds = CGDisplayBounds(display)
    let pixelWidth = CGFloat(CGDisplayPixelsWide(display))
    guard bounds.width > 0 else { return 1 }
    return max(1, Int((pixelWidth / bounds.width).rounded()))
}

func printDisplayInfo() {
    let display = CGMainDisplayID()
    let bounds = CGDisplayBounds(display)
    print("frame=\(Int(bounds.width))x\(Int(bounds.height))|pixels=\(CGDisplayPixelsWide(display))x\(CGDisplayPixelsHigh(display))|scale=\(displayScale(display))")
}

func printDisplayModes() {
    let display = CGMainDisplayID()
    guard let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] else {
        print("No display modes were returned")
        return
    }
    for mode in modes.sorted(by: { $0.height == $1.height ? $0.width < $1.width : $0.height < $1.height }) {
        print("mode|" + String(Int(mode.width)) + "x" + String(Int(mode.height)) + "|pixels=" + String(mode.pixelWidth) + "x" + String(mode.pixelHeight) + "|refresh=" + String(mode.refreshRate))
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: render-readme-media.swift seed-clipboard | seed-echotype | window OWNER | windows | wallpaper OUT | social OUT ICON NAME TAGLINE SCREENSHOT_OR_EMPTY | profile-social OUT ICON1 ICON2 ICON3 ICON4 | banner OUT ICON1 ICON2 ICON3 ICON4\n", stderr)
    exit(2)
}

do {
    switch command {
    case "seed-clipboard":
        guard args.count == 1 else { throw MediaError(description: "seed-clipboard takes no extra arguments") }
        try seedClipboard()
    case "seed-echotype":
        guard args.count == 1 else { throw MediaError(description: "seed-echotype takes no extra arguments") }
        try seedEchoType()
    case "window":
        guard args.count == 2 else { throw MediaError(description: "window needs an owner name") }
        try printWindow(args[1])
    case "windows":
        guard args.count == 1 else { throw MediaError(description: "windows takes no extra arguments") }
        try printVisibleWindows()
    case "display-info":
        guard args.count == 1 else { throw MediaError(description: "display-info takes no extra arguments") }
        printDisplayInfo()
    case "display-modes":
        guard args.count == 1 else { throw MediaError(description: "display-modes takes no extra arguments") }
        printDisplayInfo()
        printDisplayModes()
    case "wallpaper":
        guard args.count == 2 else { throw MediaError(description: "wallpaper needs an output path") }
        try makeWallpaper(args[1])
    case "social":
        guard args.count == 6 else { throw MediaError(description: "social needs output, icon, name, tagline, and a screenshot path or empty string") }
        try makeSocialPreview(args[1], args[2], args[3], args[4], args[5])
    case "profile-social":
        guard args.count == 6 else { throw MediaError(description: "profile-social needs output plus four icon paths") }
        try makeProfileSocial(args[1], Array(args[2...5]))
    case "banner":
        guard args.count == 6 else { throw MediaError(description: "banner needs output plus four icon paths") }
        try makeBanner(args[1], Array(args[2...5]))
    default:
        throw MediaError(description: "Unknown command: \(command)")
    }
} catch {
    fputs("readme media helper: \(error)\n", stderr)
    exit(1)
}
