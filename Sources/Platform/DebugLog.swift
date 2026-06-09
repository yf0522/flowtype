import Foundation

/// 诊断日志（默认关闭）。需要排查时把 enabled 改为 true，会追加到 /tmp/flowtype.log。
private let flogEnabled = false

func flog(_ msg: String) {
    guard flogEnabled else { return }
    let line = "[\(Date())] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/flowtype.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
