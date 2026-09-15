import AppKit
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

struct WindowFrameMeasurementResult: Codable {
    struct Frame: Codable {
        let index: Int
        let timestampNS: UInt64
        let relativeToEventMS: Double
        let matchesFinal: Bool
    }

    let eventPostedNS: UInt64
    let firstCorrectFrameNS: UInt64
    let firstCorrectFrameMS: Double
    let capturedFrameCount: Int
    let frames: [Frame]
    let beforeImage: String
    let firstCorrectImage: String
    let finalImage: String
}

enum WindowFrameMeasurementError: Error, LocalizedError {
    case screenPermission
    case windowNotFound(String)
    case noPreEventFrame
    case noStableFinalFrame
    case invalidROI
    case imageEncoding

    var errorDescription: String? {
        switch self {
        case .screenPermission:
            "Screen Recording permission is required for retained frame measurement."
        case .windowNotFound(let title):
            "No ScreenCaptureKit window exactly matches \(title)."
        case .noPreEventFrame:
            "The frame capture did not produce a pre-event frame."
        case .noStableFinalFrame:
            "The measured region did not reach one final state for three consecutive frames."
        case .invalidROI:
            "The frame-measurement region is empty or outside the target window."
        case .imageEncoding:
            "Could not encode retained frame evidence."
        }
    }
}

enum WindowFrameMeasurement {
    private struct CapturedFrame {
        let timestampNS: UInt64
        let image: CGImage
    }

    private final class Collector: NSObject, SCStreamOutput, SCStreamDelegate {
        let queue = DispatchQueue(label: "com.songbird.ui-probe.frames", qos: .userInitiated)
        private let lock = NSLock()
        private let context = CIContext(options: [.cacheIntermediates: false])
        private let roi: CGRect
        private let windowSize: CGSize
        private var storage: [CapturedFrame] = []

        init(roi: CGRect, windowSize: CGSize) {
            self.roi = roi
            self.windowSize = windowSize
        }

        var frames: [CapturedFrame] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of outputType: SCStreamOutputType
        ) {
            guard outputType == .screen,
                  sampleBuffer.isValid,
                  let pixelBuffer = sampleBuffer.imageBuffer else {
                return
            }
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            let scaleX = source.extent.width / windowSize.width
            let scaleY = source.extent.height / windowSize.height
            let pixelROI = CGRect(
                x: roi.minX * scaleX,
                y: source.extent.height - roi.maxY * scaleY,
                width: roi.width * scaleX,
                height: roi.height * scaleY
            ).intersection(source.extent)
            guard pixelROI.isEmpty == false else { return }
            let cropped = source.cropped(to: pixelROI)
            let downsample = min(1, 256 / max(pixelROI.width, pixelROI.height))
            let normalized = cropped
                .transformed(by: CGAffineTransform(
                    translationX: -pixelROI.minX,
                    y: -pixelROI.minY
                ))
                .transformed(by: CGAffineTransform(scaleX: downsample, y: downsample))
            guard let image = context.createCGImage(normalized, from: normalized.extent) else {
                return
            }
            let frame = CapturedFrame(
                timestampNS: DispatchTime.now().uptimeNanoseconds,
                image: image
            )
            lock.lock()
            if storage.count < 360 { storage.append(frame) }
            lock.unlock()
        }
    }

    private final class ActiveCapture {
        let stream: SCStream
        let collector: Collector

        init(stream: SCStream, collector: Collector) {
            self.stream = stream
            self.collector = collector
        }
    }

    static func measure(
        processID: pid_t,
        windowTitle: String,
        roi: CGRect,
        duration: TimeInterval,
        outputDirectory: URL,
        postAction: () throws -> UInt64
    ) throws -> WindowFrameMeasurementResult {
        guard CGPreflightScreenCaptureAccess() else {
            throw WindowFrameMeasurementError.screenPermission
        }
        let active = try awaitValue {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let matches = content.windows.filter {
                $0.owningApplication?.processID == processID && $0.title == windowTitle
            }
            guard matches.count == 1, let window = matches.first else {
                throw WindowFrameMeasurementError.windowNotFound(windowTitle)
            }
            guard roi.width > 0, roi.height > 0,
                  CGRect(origin: .zero, size: window.frame.size).contains(roi) else {
                throw WindowFrameMeasurementError.invalidROI
            }
            let collector = Collector(roi: roi, windowSize: window.frame.size)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width * 2))
            configuration.height = max(1, Int(window.frame.height * 2))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 8
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let stream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: collector
            )
            try stream.addStreamOutput(
                collector,
                type: .screen,
                sampleHandlerQueue: collector.queue
            )
            try await stream.startCapture()
            return ActiveCapture(stream: stream, collector: collector)
        }

        let preframeDeadline = Date().addingTimeInterval(1)
        while active.collector.frames.isEmpty, Date() < preframeDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        let eventPostedNS = try postAction()
        Thread.sleep(forTimeInterval: max(0.25, min(duration, 5)))
        try awaitValue { try await active.stream.stopCapture() }
        Thread.sleep(forTimeInterval: 0.05)

        let frames = active.collector.frames
        guard let before = frames.last(where: { $0.timestampNS < eventPostedNS }) else {
            throw WindowFrameMeasurementError.noPreEventFrame
        }
        let postEventFrames = frames.filter { $0.timestampNS >= eventPostedNS }
        guard postEventFrames.count >= 3, let final = postEventFrames.last else {
            throw WindowFrameMeasurementError.noStableFinalFrame
        }
        let finalPixels = normalizedPixels(final.image)
        let matches = postEventFrames.map { frame in
            pixelsMatch(normalizedPixels(frame.image), finalPixels)
        }
        var firstCorrectIndex: Int?
        if matches.count >= 3 {
            for index in 0...(matches.count - 3) where matches[index...index + 2].allSatisfy({ $0 }) {
                firstCorrectIndex = index
                break
            }
        }
        guard let firstCorrectIndex else {
            throw WindowFrameMeasurementError.noStableFinalFrame
        }
        let firstCorrect = postEventFrames[firstCorrectIndex]
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let beforeURL = outputDirectory.appendingPathComponent("before.png")
        let firstURL = outputDirectory.appendingPathComponent("first-correct.png")
        let finalURL = outputDirectory.appendingPathComponent("final.png")
        try writePNG(before.image, to: beforeURL)
        try writePNG(firstCorrect.image, to: firstURL)
        try writePNG(final.image, to: finalURL)

        let frameRecords = postEventFrames.enumerated().map { index, frame in
            WindowFrameMeasurementResult.Frame(
                index: index,
                timestampNS: frame.timestampNS,
                relativeToEventMS: Double(frame.timestampNS - eventPostedNS) / 1_000_000,
                matchesFinal: matches[index]
            )
        }
        let result = WindowFrameMeasurementResult(
            eventPostedNS: eventPostedNS,
            firstCorrectFrameNS: firstCorrect.timestampNS,
            firstCorrectFrameMS: Double(firstCorrect.timestampNS - eventPostedNS) / 1_000_000,
            capturedFrameCount: frames.count,
            frames: frameRecords,
            beforeImage: beforeURL.path,
            firstCorrectImage: firstURL.path,
            finalImage: finalURL.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(result).write(
            to: outputDirectory.appendingPathComponent("frame-times.json"),
            options: .atomic
        )
        return result
    }

    private static func awaitValue<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<T, Error>?
        Task {
            let completed: Result<T, Error>
            do {
                completed = .success(try await operation())
            } catch {
                completed = .failure(error)
            }
            lock.withLock { result = completed }
            semaphore.signal()
        }
        semaphore.wait()
        return try lock.withLock { try result!.get() }
    }

    private static func normalizedPixels(_ image: CGImage) -> [UInt8] {
        let width = 128
        let height = max(1, Int(Double(image.height) / Double(max(1, image.width)) * 128))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func pixelsMatch(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count, lhs.isEmpty == false else { return false }
        var absoluteDifference = 0
        var closeChannelCount = 0
        for index in lhs.indices {
            let difference = abs(Int(lhs[index]) - Int(rhs[index]))
            absoluteDifference += difference
            if difference <= 8 { closeChannelCount += 1 }
        }
        let normalizedMean = Double(absoluteDifference) / Double(lhs.count * 255)
        let closeFraction = Double(closeChannelCount) / Double(lhs.count)
        return normalizedMean <= 0.005 && closeFraction >= 0.99
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw WindowFrameMeasurementError.imageEncoding
        }
        try data.write(to: url, options: .atomic)
    }
}
