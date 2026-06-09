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
    /// 上一条识别结果的时间（用于区分"停顿换句"与"中途抖动"）。
    private var lastResultAt: Date?

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
        lastResultAt = nil

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
                let new = result.bestTranscription.formattedString
                // 关键修复：on-device 识别器换句时会把 partial 重置成新语段(不发 isFinal)。
                // 信号：新文本既不是上一段的延续，且长度骤降(<上一段一半)=语段重置 → 提交上一段，避免覆盖。
                // 中途修正(等长/变长)不会触发，避免切碎。
                if !self.partial.isEmpty,
                   !Self.isContinuation(prev: self.partial, new: new),
                   new.count < self.partial.count / 2 {
                    self.commitSegment(self.partial)
                }
                self.partial = new
                flog("STT: isFinal=\(result.isFinal) partial=「\(new)」committed=「\(self.committed)」")
                self.onTranscript?(self.displayText, false)
                if result.isFinal {
                    self.commitSegment(self.partial)
                    self.partial = ""
                    self.startTask()
                }
            }
            if let error { flog("STT: error=\(error)") }
        }
    }

    /// 判断 new 是否是 prev 的延续（增长/小幅修正），而非全新语段。
    private static func isContinuation(prev: String, new: String) -> Bool {
        if new.hasPrefix(prev) || prev.hasPrefix(new) { return true }
        return new.commonPrefix(with: prev).count >= max(1, prev.count / 2)
    }

    /// 把一段定稿文本并入 committed。段尾已有标点则不再加逗号，过短碎片(<2字)丢弃。
    private func commitSegment(_ seg: String) {
        let s = seg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 2 else { return }
        if let last = s.last, "。！？，、；：".contains(last) {
            committed += s
        } else {
            committed += s + "，"
        }
    }

    func stop() -> String {
        session.stopRunning()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        var text = committed + partial.trimmingCharacters(in: .whitespacesAndNewlines)
        committed = ""; partial = ""
        // 末尾标点收尾：去掉尾逗号，无句末标点则补句号
        if text.hasSuffix("，") { text.removeLast() }
        if let last = text.last, !"。！？，".contains(last) { text += "。" }
        flog("STT: stop() 最终文本=「\(text)」")
        return text
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
