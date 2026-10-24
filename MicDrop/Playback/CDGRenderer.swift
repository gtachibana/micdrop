import QuartzCore
import UIKit

/// Drives a CDGDecoder from a playback clock and pushes frames to any attached layers
/// (the phone's stage and, when connected, the TV's stage).
@MainActor
final class CDGRenderer: NSObject {
    private var decoder: CDGDecoder?
    private var timeSource: (() -> Double)?
    private var displayLink: CADisplayLink?
    private let layers = NSHashTable<CALayer>.weakObjects()
    private(set) var image: CGImage?

    func load(_ decoder: CDGDecoder, timeSource: @escaping () -> Double) {
        self.decoder = decoder
        self.timeSource = timeSource
        decoder.advance(to: timeSource())
        image = decoder.makeImage()
        publish()
    }

    func unload() {
        stop()
        decoder = nil
        timeSource = nil
        image = nil
        publish()
    }

    func attach(_ layer: CALayer) {
        layers.add(layer)
        layer.contents = image
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step() {
        guard let decoder, let timeSource else { return }
        if decoder.advance(to: timeSource()) {
            image = decoder.makeImage()
            publish()
        }
    }

    private func publish() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.allObjects {
            layer.contents = image
        }
        CATransaction.commit()
    }
}
