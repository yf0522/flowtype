import Foundation

/// 听写引擎抽象，便于协调器解耦具体实现。
protocol SpeechRecognizing: AnyObject {
    /// 部分/最终转写回调：(文本, 是否最终)
    var onTranscript: ((String, Bool) -> Void)? { get set }
    /// 实时音频电平回调，0...1，用于波形。
    var onLevel: ((Float) -> Void)? { get set }
    func start(locale: String) throws
    /// 停止并返回最终文本。
    func stop() -> String
}

enum SpeechError: Error { case onDeviceUnavailable, notAuthorized, engineFailure }
