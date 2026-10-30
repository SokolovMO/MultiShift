import AppKit
import ScreenCaptureKit
import AVFoundation

@available(macOS 14.0, *)
final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, CMSampleBufferGetImageBuffer(buffer) != nil else { return }
        if !started { writer.startWriting(); writer.startSession(atSourceTime: buffer.presentationTimeStamp); started = true }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }
}

@main struct Main {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "com.multiswitcher.multishift" && $0.title == "настройки" }) else {
            throw NSError(domain: "No settings window", code: 1)
        }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        let recorder = try Recorder(url: URL(fileURLWithPath: CommandLine.arguments[1]), width: config.width, height: config.height)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        print("recording window \(window.windowID) at \(config.width)x\(config.height)")
        try await Task.sleep(for: .seconds(Int(CommandLine.arguments[2]) ?? 15))
        try? await stream.stopCapture()
        recorder.input.markAsFinished()
        await recorder.writer.finishWriting()
        print("video status \(recorder.writer.status.rawValue)")
    }
}
