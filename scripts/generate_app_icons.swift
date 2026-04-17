import AppKit

struct IconSpec {
  let path: String
  let size: CGFloat
}

let fileManager = FileManager.default
let root = fileManager.currentDirectoryPath

let specs: [IconSpec] = [
  .init(path: "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", size: 48),
  .init(path: "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", size: 72),
  .init(path: "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", size: 96),
  .init(path: "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", size: 144),
  .init(path: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", size: 192),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png", size: 20),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png", size: 40),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png", size: 60),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png", size: 29),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png", size: 58),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png", size: 87),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png", size: 40),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png", size: 80),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png", size: 120),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png", size: 120),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png", size: 180),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png", size: 76),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png", size: 152),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png", size: 167),
  .init(path: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png", size: 1024),
]

func exportIcon(to path: String, size: CGFloat) throws {
  let pixelSize = Int(size.rounded())
  let rect = CGRect(x: 0, y: 0, width: size, height: size)

  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw NSError(domain: "IconGen", code: 1)
  }

  bitmap.size = NSSize(width: size, height: size)
  NSGraphicsContext.saveGraphicsState()
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
    throw NSError(domain: "IconGen", code: 1)
  }
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)

  let radius = size * 0.225
  let iconPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  context.saveGState()
  iconPath.addClip()

  let colors = [
    NSColor(calibratedRed: 228/255, green: 106/255, blue: 17/255, alpha: 1).cgColor,
    NSColor(calibratedRed: 255/255, green: 142/255, blue: 43/255, alpha: 1).cgColor,
    NSColor(calibratedRed: 255/255, green: 177/255, blue: 90/255, alpha: 1).cgColor,
  ] as CFArray
  let locations: [CGFloat] = [0.0, 0.58, 1.0]
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
  )

  let glowColor = NSColor.white.withAlphaComponent(0.14).cgColor
  context.setFillColor(glowColor)
  context.fillEllipse(in: CGRect(x: size * 0.56, y: size * 0.60, width: size * 0.34, height: size * 0.24))
  context.fillEllipse(in: CGRect(x: size * 0.10, y: size * 0.08, width: size * 0.30, height: size * 0.22))

  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
  shadow.shadowBlurRadius = size * 0.055
  shadow.shadowOffset = NSSize(width: 0, height: -(size * 0.03))
  shadow.set()

  let white = NSColor.white
  white.setFill()

  let wallet = NSBezierPath(roundedRect: CGRect(
    x: size * 0.215,
    y: size * 0.28,
    width: size * 0.57,
    height: size * 0.41
  ), xRadius: size * 0.11, yRadius: size * 0.11)
  wallet.fill()

  let flap = NSBezierPath(roundedRect: CGRect(
    x: size * 0.27,
    y: size * 0.50,
    width: size * 0.46,
    height: size * 0.11
  ), xRadius: size * 0.055, yRadius: size * 0.055)
  flap.fill()

  let cutout = NSBezierPath(roundedRect: CGRect(
    x: size * 0.58,
    y: size * 0.43,
    width: size * 0.12,
    height: size * 0.11
  ), xRadius: size * 0.04, yRadius: size * 0.04)
  NSColor(calibratedRed: 176/255, green: 78/255, blue: 21/255, alpha: 0.22).setFill()
  cutout.fill()

  let bolt = NSBezierPath()
  bolt.move(to: CGPoint(x: size * 0.48, y: size * 0.70))
  bolt.line(to: CGPoint(x: size * 0.40, y: size * 0.52))
  bolt.line(to: CGPoint(x: size * 0.49, y: size * 0.52))
  bolt.line(to: CGPoint(x: size * 0.43, y: size * 0.34))
  bolt.line(to: CGPoint(x: size * 0.60, y: size * 0.55))
  bolt.line(to: CGPoint(x: size * 0.51, y: size * 0.55))
  bolt.close()
  NSColor(calibratedRed: 255/255, green: 230/255, blue: 179/255, alpha: 1).setFill()
  bolt.fill()

  context.restoreGState()
  NSGraphicsContext.restoreGraphicsState()

  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "IconGen", code: 2)
  }

  let destination = URL(fileURLWithPath: root).appendingPathComponent(path)
  try data.write(to: destination)
}

do {
  for spec in specs {
    try exportIcon(to: spec.path, size: spec.size)
  }
  print("Generated \(specs.count) app icons.")
} catch {
  fputs("Icon generation failed: \(error)\n", stderr)
  exit(1)
}
