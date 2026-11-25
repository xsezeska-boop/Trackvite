import Foundation
import ScreenCaptureKit
import Vision
import VideoToolbox

/// All mutable state is confined to `queue`. No recording output or frame archive.
final class LiveScreenAnalyzer: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "tracker.frames", qos: .background)
    private let ocrQueue = DispatchQueue(label: "tracker.ocr", qos: .background)
    var onText: ((UUID, String, String) -> Void)?
    var onError: ((String) -> Void)?
    private var token = UUID()
    private var enabled = false
    private var pending: (CGImage, [UInt8])?
    private var gate = FrameChangeGate()
    private var inFlight = false
    private var scheduled: DispatchWorkItem?
    private var lastOCR = Date.distantPast
    private var lastOCRDuration: Double = 0
    private var frames = 0
    private var skipped = 0
    private var recognitions = 0

    func setContext(_ token: UUID, enabled: Bool) {
        queue.async {
            self.token = token
            self.enabled = enabled
            self.pending = nil
            self.gate.reset()
            self.scheduled?.cancel()
            self.scheduled = nil
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            self.enabled = false
            self.pending = nil
            self.scheduled?.cancel()
            self.scheduled = nil
            self.onError?("macOS error \((error as NSError).code)")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard enabled, type == .screen, sample.isValid,
              let metadata = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = metadata[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sample.imageBuffer else { return }
        frames += 1
        if let rects = metadata[.dirtyRects] as? [CGRect], rects.isEmpty {
            skipped += 1
            return
        }
        var output: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &output) == noErr,
              let image = output else { return }
        var signature = [UInt8](repeating: 0, count: 64 * 40)
        let rendered = signature.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 40,
                bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 40))
            return true
        }
        if rendered && !gate.shouldAnalyze(signature) {
            pending = nil
            skipped += 1
            return
        }
        // Replace, never enqueue: at most one current frame waits for OCR.
        pending = (image, signature)
        schedule()
    }

    private func schedule() {
        guard enabled, !inFlight, scheduled == nil, pending != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.recognize() }
        scheduled = work
        // Let UI settle, but don't postpone indefinitely while typing/scrolling.
        let power = ProcessInfo.processInfo
        let constrained = power.isLowPowerModeEnabled || power.thermalState == .serious || power.thermalState == .critical
        let interval = OCRBudget.interval(duration: lastOCRDuration, constrained: constrained)
        let delay = max(0.6, interval - Date().timeIntervalSince(lastOCR))
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func recognize() {
        scheduled = nil
        guard enabled, !inFlight, let (image, signature) = pending else { return }
        if ProcessInfo.processInfo.thermalState == .critical {
            // Do not run OCR when macOS reports critical thermal pressure.
            pending = nil
            return
        }
        pending = nil
        gate.recordAnalyzed(signature)
        inFlight = true
        lastOCR = Date()
        let contextToken = token
        ocrQueue.async {
            let started = Date()
            let result: Result<String, Error> = Result {
                try autoreleasepool {
                    let request = VNRecognizeTextRequest()
                    request.preferBackgroundProcessing = true
                    request.recognitionLevel = .fast
                    request.usesLanguageCorrection = false
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n").prefix(2_000))
                }
            }
            self.queue.async {
                self.lastOCRDuration = Date().timeIntervalSince(started)
                self.inFlight = false
                if self.enabled && self.token == contextToken {
                    self.recognitions += 1
                    let stats = "Changes: \(self.frames) · skipped: \(self.skipped) · readings: \(self.recognitions) · last: \(Int(self.lastOCRDuration * 1000)) ms"
                    switch result {
                    case .success(let text): self.onText?(contextToken, text, stats)
                    case .failure(let error):
                        self.gate.reset()
                        self.onText?(contextToken, "Text recognition unavailable. Error \((error as NSError).code)", stats)
                    }
                }
                self.schedule()
            }
        }
    }
}
