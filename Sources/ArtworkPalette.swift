import AppKit

/// Colores dominantes de una carátula (como Apple Music / Spotify):
/// cuantiza la imagen, puntúa cada color por presencia y viveza, e ignora fondos negros/blancos.
struct ArtworkPalette: Equatable {
    let primary: NSColor      // color más característico
    let secondary: NSColor    // segundo color, de otro tono (o variante del primero)
    let isMonochrome: Bool    // carátula casi en blanco y negro

    /// Color vivo para el ecualizador y la barra de progreso.
    var accent: NSColor {
        if isMonochrome { return NSColor(white: 0.85, alpha: 1) }
        let (h, s, b) = primary.hsb
        return NSColor(hue: h, saturation: min(max(s, 0.45), 0.9), brightness: max(b, 0.85), alpha: 1)
    }

    /// Degradado de fondo para la isla (oscuro, saturado, legible con texto blanco).
    var background: [NSColor] {
        if isMonochrome {
            let (_, _, b) = primary.hsb
            let top = 0.16 + 0.10 * b
            return [NSColor(white: top, alpha: 1), NSColor(white: 0.07, alpha: 1)]
        }
        let (h1, s1, _) = primary.hsb
        let (h2, s2, _) = secondary.hsb
        return [
            NSColor(hue: h1, saturation: min(max(s1 * 1.1, 0.45), 0.9), brightness: 0.46, alpha: 1),
            NSColor(hue: h2, saturation: min(max(s2 * 1.1, 0.40), 0.9), brightness: 0.22, alpha: 1)
        ]
    }

    static func extract(from image: NSImage) -> ArtworkPalette? {
        let side = 40
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Cubetas de 4 bits por canal
        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, n = 0 }
        var buckets: [Int: Bucket] = [:]
        var satSum = 0.0
        for i in 0..<(side * side) {
            let r = Double(px[i * 4]) / 255, g = Double(px[i * 4 + 1]) / 255, b = Double(px[i * 4 + 2]) / 255
            let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
            var bk = buckets[key] ?? Bucket()
            bk.r += r; bk.g += g; bk.b += b; bk.n += 1
            buckets[key] = bk
            let mx = max(r, g, b), mn = min(r, g, b)
            satSum += mx > 0 ? (mx - mn) / mx : 0
        }
        let total = Double(side * side)
        let monochrome = satSum / total < 0.12

        // Puntuación: presencia × viveza, penalizando casi-negro y casi-blanco
        var scored: [(color: NSColor, score: Double, hue: CGFloat)] = []
        for bk in buckets.values where bk.n >= 3 {
            let c = NSColor(srgbRed: bk.r / Double(bk.n), green: bk.g / Double(bk.n), blue: bk.b / Double(bk.n), alpha: 1)
            let (h, s, v) = c.hsb
            var score = Double(bk.n) / total
            if monochrome {
                score *= (v > 0.08 && v < 0.95) ? 1 : 0.3
            } else {
                if v < 0.15 || (v > 0.92 && s < 0.15) { score *= 0.05 }   // fondos negros / blancos
                score *= 0.25 + Double(s) * 1.6                           // premiar color vivo
                score *= 0.6 + Double(min(v, 0.85))                        // y luminoso
            }
            scored.append((c, score, h))
        }
        scored.sort { $0.score > $1.score }
        guard let first = scored.first else { return nil }

        // Secundario: el mejor con un tono claramente distinto
        let second = scored.dropFirst().first { cand in
            let d = abs(cand.hue - first.hue)
            return min(d, 1 - d) > 0.08 && cand.color.hsb.s > 0.2
        }?.color ?? first.color.blended(withFraction: 0.35, of: .black) ?? first.color

        return ArtworkPalette(primary: first.color, secondary: second, isMonochrome: monochrome)
    }
}

extension NSColor {
    var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = usingColorSpace(.sRGB) ?? self
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }
}
