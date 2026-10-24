import CoreGraphics
import Foundation

private let screenWidth = 300
private let screenHeight = 216
private let packetSize = 24

/// Decoder for CD+G karaoke graphics.
///
/// A .cdg file is a stream of 24-byte subcode packets played at 300 packets per second.
/// Each packet may draw into a 300x216 bitmap of 4-bit colour indices; the visible area
/// is the 288x192 interior, surrounded by a border drawn in a single colour.
final class CDGDecoder {
    static let packetsPerSecond = 300.0

    private let bytes: [UInt8]
    let packetCount: Int

    private var pixels = [UInt8](repeating: 0, count: screenWidth * screenHeight)
    private var red = [UInt8](repeating: 0, count: 16)
    private var green = [UInt8](repeating: 0, count: 16)
    private var blue = [UInt8](repeating: 0, count: 16)
    private var borderColor: UInt8 = 0
    private var hOffset = 0
    private var vOffset = 0
    private var position = 0
    private var rgba = [UInt8](repeating: 255, count: screenWidth * screenHeight * 4)

    init(data: Data) {
        bytes = [UInt8](data)
        packetCount = bytes.count / packetSize
    }

    convenience init(contentsOf url: URL) throws {
        self.init(data: try Data(contentsOf: url))
    }

    var duration: Double { Double(packetCount) / Self.packetsPerSecond }

    func reset() {
        for i in pixels.indices { pixels[i] = 0 }
        for i in 0..<16 { red[i] = 0; green[i] = 0; blue[i] = 0 }
        borderColor = 0
        hOffset = 0
        vOffset = 0
        position = 0
    }

    /// Processes packets up to `time` seconds. Seeking backwards replays from the start,
    /// since CD+G drawing is cumulative. Returns true if the screen may have changed.
    @discardableResult
    func advance(to time: Double) -> Bool {
        let target = min(packetCount, max(0, Int(time * Self.packetsPerSecond)))
        var changed = false
        if target < position {
            reset()
            changed = true
        }
        while position < target {
            if process(packetAt: position * packetSize) { changed = true }
            position += 1
        }
        return changed
    }

    // MARK: - Packet handling

    private func process(packetAt offset: Int) -> Bool {
        guard bytes[offset] & 0x3F == 9 else { return false }
        let data = offset + 4
        switch bytes[offset + 1] & 0x3F {
        case 1: memoryPreset(color: bytes[data] & 0x0F)
        case 2: borderColor = bytes[data] & 0x0F
        case 6: tileBlock(at: data, xor: false)
        case 38: tileBlock(at: data, xor: true)
        case 20: scroll(at: data, copy: false)
        case 24: scroll(at: data, copy: true)
        case 30: loadColors(at: data, startingAt: 0)
        case 31: loadColors(at: data, startingAt: 8)
        default: return false
        }
        return true
    }

    private func memoryPreset(color: UInt8) {
        for i in pixels.indices { pixels[i] = color }
    }

    private func tileBlock(at data: Int, xor: Bool) {
        let color0 = bytes[data] & 0x0F
        let color1 = bytes[data + 1] & 0x0F
        let row = Int(bytes[data + 2] & 0x1F)
        let column = Int(bytes[data + 3] & 0x3F)
        guard row < 18, column < 50 else { return }
        let x0 = column * 6
        let y0 = row * 12
        for line in 0..<12 {
            let bits = bytes[data + 4 + line] & 0x3F
            let base = (y0 + line) * screenWidth + x0
            for bit in 0..<6 {
                let color = (bits >> (5 - bit)) & 1 == 1 ? color1 : color0
                if xor {
                    pixels[base + bit] ^= color
                } else {
                    pixels[base + bit] = color
                }
            }
        }
    }

    private func scroll(at data: Int, copy: Bool) {
        let fill = bytes[data] & 0x0F
        let h = bytes[data + 1] & 0x3F
        let v = bytes[data + 2] & 0x3F
        hOffset = min(Int(h & 0x07), 5)
        vOffset = min(Int(v & 0x0F), 11)

        let dx: Int
        switch (h & 0x30) >> 4 {
        case 1: dx = 6
        case 2: dx = -6
        default: dx = 0
        }
        let dy: Int
        switch (v & 0x30) >> 4 {
        case 1: dy = 12
        case 2: dy = -12
        default: dy = 0
        }
        guard dx != 0 || dy != 0 else { return }

        let old = pixels
        for y in 0..<screenHeight {
            for x in 0..<screenWidth {
                var sx = x - dx
                var sy = y - dy
                if copy {
                    sx = (sx + screenWidth) % screenWidth
                    sy = (sy + screenHeight) % screenHeight
                } else if sx < 0 || sx >= screenWidth || sy < 0 || sy >= screenHeight {
                    pixels[y * screenWidth + x] = fill
                    continue
                }
                pixels[y * screenWidth + x] = old[sy * screenWidth + sx]
            }
        }
    }

    private func loadColors(at data: Int, startingAt first: Int) {
        for i in 0..<8 {
            let high = bytes[data + 2 * i] & 0x3F
            let low = bytes[data + 2 * i + 1] & 0x3F
            let r = (high & 0x3C) >> 2
            let g = ((high & 0x03) << 2) | ((low & 0x30) >> 4)
            let b = low & 0x0F
            red[first + i] = r * 17
            green[first + i] = g * 17
            blue[first + i] = b * 17
        }
    }

    // MARK: - Rendering

    func makeImage() -> CGImage? {
        let r = red, g = green, b = blue
        let border = Int(borderColor)
        let hOff = hOffset, vOff = vOffset
        pixels.withUnsafeBufferPointer { px in
            rgba.withUnsafeMutableBufferPointer { out in
                for y in 0..<screenHeight {
                    let interiorRow = y >= 12 && y < 204
                    for x in 0..<screenWidth {
                        let index: Int
                        if interiorRow && x >= 6 && x < 294 {
                            index = Int(px[(y + vOff) * screenWidth + x + hOff])
                        } else {
                            index = border
                        }
                        let o = (y * screenWidth + x) * 4
                        out[o] = r[index]
                        out[o + 1] = g[index]
                        out[o + 2] = b[index]
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: screenWidth,
            height: screenHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: screenWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
