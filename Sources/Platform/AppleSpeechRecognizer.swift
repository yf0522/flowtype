import Foundation
import AVFoundation
import Speech

/// 基于 Apple 本地 SFSpeechRecognizer 的实现。参考 Muxy 同款方案。
final class AppleSpeechRecognizer: NSObject, SpeechRecognizing, @unchecked Sendable {
    var onTranscript: ((String, Bool) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "flowtype.audio")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastText = ""

    func start(locale: String) throws {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw SpeechError.engineFailure
        }
        guard rec.supportsOnDeviceRecognition else { throw SpeechError.onDeviceUnavailable }
        rec.defaultTaskHint = .dictation
        recognizer = rec
        lastText = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req

        // 配置采集
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            throw SpeechError.engineFailure
        }
        session.addInput(input)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        session.commitConfiguration()

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.lastText = result.bestTranscription.formattedString
                self.onTranscript?(self.lastText, result.isFinal)
            }
            if error != nil { /* 交由 stop 收尾 */ }
        }

        session.startRunning()
    }

    func stop() -> String {
        session.stopRunning()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        return lastText
    }
}

extension AppleSpeechRecognizer: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        request?.appendAudioSampleBuffer(sampleBuffer)
        // 粗略电平：取样本绝对均值
        if let level = sampleBuffer.approxLevel { onLevel?(level) }
    }
}

private extension CMSampleBuffer {
    /// 简单的 RMS 近似，用于波形 UI（非精确）。
    var approxLevel: Float? {
        guard let bb = CMSampleBufferGetDataBuffer(self) else { return nil }
        var length = 0; var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let ptr = dataPointer, length > 1 else { return nil }
        let count = length / 2
        let samples = ptr.withMemoryRebound(to: Int16.self, capacity: count) { p in
            UnsafeBufferPointer(start: p, count: count)
        }
        var sum: Float = 0
        for s in samples { let v = Float(s) / 32768.0; sum += v * v }
        return min(1, sqrt(sum / Float(count)) * 4)
    }
}
