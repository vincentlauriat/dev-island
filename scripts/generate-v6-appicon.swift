#!/usr/bin/env swift
// Renders the canonical Dev Island app icon source bitmap.
//
// Produces a single 1024×1024 PNG at Assets/Brand/app-icon-v6.png. That
// image is the sole "master" — the Python pipeline
// (scripts/generate_brand_icons.py) resizes it into every
// AppIcon.appiconset slot and then composes DevIsland.icns. Re-run this
// script after any design tweak, then run the Python pipeline.
//
// Spec — "Spectacles in the island" (fork-specific; upstream ships Bar+Dot):
// - Paper tone: background #EDE9FE, mark #2E1065, foreground #EDE9FE (fork palette;
//   upstream's warm pair was #f1ead9 / #0d0d0f)
// - Outer squircle: corner radius = size * 0.225 (full-bleed, no shadow
//   baked in — macOS supplies its own drop shadow)
// - Inner mark in a 160×64 viewBox, scaled to 72% of outer width: a fully
//   rounded pill (the island) carrying a pair of round spectacles — two
//   outlined lenses, a bridge, and temples running out to the pill ends.
// - 1px ink ring at rgba(0,0,0,0.06) for edge crispness
//
// Why outlines rather than filled lenses: filled discs read as eyes or a power
// socket. The bridge is what makes the shape parse as spectacles, and the
// temples are what tie the frame into the island instead of leaving it afloat
// with dead ink at both ends. Checked at 32px — the size the menu bar uses —
// where thin strokes are the first thing to close up.

import AppKit
import CoreGraphics
import Foundation

let outputPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/Brand/app-icon-v6.png")

// Fork palette. Upstream ships warm paper (#f1ead9) + near-black ink; Dev Island uses a violet
// pair so the two apps are told apart at a glance in the Dock when both are installed.
let paper = CGColor(red: 0xED/255.0, green: 0xE9/255.0, blue: 0xFE/255.0, alpha: 1)
let ink   = CGColor(red: 0x2E/255.0, green: 0x10/255.0, blue: 0x65/255.0, alpha: 1)
let ring  = CGColor(red: 0, green: 0, blue: 0, alpha: 0.06)

// Mark geometry, in 160×64 viewBox units.
let lensRadius: CGFloat = 22
let lensLeftX: CGFloat = 52
let lensRightX: CGFloat = 108
let lensCenterY: CGFloat = 32
let strokeWeight: CGFloat = 6
let templeLeftEnd: CGFloat = 14    // stops short of the pill edge so ink keeps a margin
let templeRightEnd: CGFloat = 146

func render(px: Int) -> Data {
    let size = CGFloat(px)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }

    // Transparent canvas.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Full-bleed squircle. The Python pipeline insets this to the macOS
    // icon content grid (824/1024), so no extra padding is baked in here.
    let radius = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.setFillColor(paper)
    ctx.addPath(squircle)
    ctx.fillPath()

    // 1px inset ring for edge definition at small sizes.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(ring)
    ctx.setLineWidth(size / 1024.0)
    ctx.strokePath()
    ctx.restoreGState()

    // Clip to squircle so the mark corners can't bleed.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // The island: a fully rounded pill (corner radius = h/2), centered.
    let markW = rect.width * 0.72
    let markH = markW * 64.0 / 160.0
    let markRect = CGRect(
        x: rect.midX - markW / 2,
        y: rect.midY - markH / 2,
        width: markW,
        height: markH
    )
    let u = markW / 160.0   // one viewBox unit, in points

    let pill = CGPath(
        roundedRect: markRect,
        cornerWidth: markH / 2,
        cornerHeight: markH / 2,
        transform: nil
    )
    ctx.setFillColor(ink)
    ctx.addPath(pill)
    ctx.fillPath()

    // viewBox point -> device point. CG origin is bottom-left, and the mark is
    // vertically symmetric, so no Y flip is needed.
    func vb(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: markRect.minX + x * u, y: markRect.minY + y * u)
    }

    let leftC = vb(lensLeftX, lensCenterY)
    let rightC = vb(lensRightX, lensCenterY)
    let r = lensRadius * u

    ctx.setStrokeColor(paper)
    ctx.setLineWidth(strokeWeight * u)
    ctx.setLineCap(.round)

    // Temples, then bridge, then lenses — drawn in that order so the lens rings
    // sit on top of the joints rather than showing seams through them.
    ctx.move(to: CGPoint(x: leftC.x - r, y: leftC.y))
    ctx.addLine(to: vb(templeLeftEnd, lensCenterY))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: rightC.x + r, y: rightC.y))
    ctx.addLine(to: vb(templeRightEnd, lensCenterY))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: leftC.x + r, y: leftC.y))
    ctx.addLine(to: CGPoint(x: rightC.x - r, y: rightC.y))
    ctx.strokePath()

    for c in [leftC, rightC] {
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return data
}

let data = render(px: 1024)
try? data.write(to: outputPath)
print("wrote \(outputPath.path) (1024×1024)")
