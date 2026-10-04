// Builds the opaque 1024x1024 App Store icon from art/PartnerLogo.png (800x400, white background).
// Usage: swift tools/make_icon.swift art/PartnerLogo.png KTXDriver/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("usage: make_icon.swift <PartnerLogo.png> <out.png>")
}

let side = 1024
// The artwork sits roughly in x 120...680 of the 800 px source; trim the side margins only.
let cropX = 120 * logo.width / 800
let cropped = logo.cropping(to: CGRect(x: cropX, y: 0, width: logo.width - 2 * cropX, height: logo.height))!
let logoWidth = 820.0
let logoHeight = logoWidth * Double(cropped.height) / Double(cropped.width)

// No alpha channel: App Store icons must be opaque.
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
ctx.draw(cropped, in: CGRect(x: (Double(side) - logoWidth) / 2, y: (Double(side) - logoHeight) / 2,
                             width: logoWidth, height: logoHeight))

let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                          UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(out) else { fatalError("could not write \(args[2])") }
