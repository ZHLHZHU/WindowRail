import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func png(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    AppArtwork.drawAppIcon(in: context.cgContext, rect: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
for pointSize in [16, 32, 128, 256, 512] {
    try png(size: pointSize, to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    try png(size: pointSize * 2, to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
try png(size: 1024, to: URL(fileURLWithPath: CommandLine.arguments[2]))
