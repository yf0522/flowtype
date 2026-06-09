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
    /// 已定稿的段落（停顿后不清空，持续累积）。
    private var committed = ""
    /// 当前段落的实时部分结果。
    private var partial = ""

    private var displayText: String { committed + partial }

    func start(locale: String) throws {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw SpeechError.engineFailure
        }
        guard rec.supportsOnDeviceRecognition else { throw SpeechError.onDeviceUnavailable }
        rec.defaultTaskHint = .dictation
        recognizer = rec
        committed = ""
        partial = ""

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

        startTask()
        session.startRunning()
    }

    /// 创建一次识别任务。段落定稿(isFinal)时把结果并入 committed 并重启任务，
    /// 这样说话中的停顿不会清空之前已说的内容。
    private func startTask() {
        guard let rec = recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        if #available(macOS 13.0, *) { req.addsPunctuation = true } // 自动加标点
        request = req

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.partial = result.bestTranscription.formattedString
                self.onTranscript?(self.displayText, false)
                if result.isFinal {
                    // 段落定稿：并入已提交文本，重启任务继续听后续
                    self.committed = self.displayText
                    self.partial = ""
                    self.startTask()
                }
            }
            if error != nil { /* 交由 stop 收尾 */ }
        }
    }

    func stop() -> String {
        session.stopRunning()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        let final = displayText
        committed = ""; partial = ""
        return final
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
