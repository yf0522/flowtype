import SwiftUI

struct RecordingHUD: View {
    @ObservedObject var vm: RecordingViewModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: iconName).font(.system(size: 13)).foregroundStyle(.white))
            WaveformView(level: vm.level)
                .frame(width: 40, height: 22)
            Text(vm.transcript.isEmpty ? "聆听中…" : vm.transcript)
                .lineLimit(1).truncationMode(.head)
                .foregroundStyle(.white)
                .frame(maxWidth: 200, alignment: .leading)
            if vm.phase == .recording {
                Button(action: { vm.onDiscard() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("丢弃")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.black.opacity(0.85), in: Capsule())
    }

    private var iconName: String {
        switch vm.phase { case .recording: "mic.fill"; case .inserting: "ellipsis"; case .done: "checkmark" }
    }
}

struct WaveformView: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(.purple)
                    .frame(width: 3, height: max(4, CGFloat(level) * 22 * heights[i]))
            }
        }
    }
    private let heights: [CGFloat] = [0.6, 1.0, 0.8, 1.0, 0.5]
}
