import SwiftUI

struct WakeDurationControl: View {
    @Binding var minutes: Int
    private let options: [(value: Int, title: String)] = [(0, "持续"), (30, "30 分钟"), (60, "1 小时"), (120, "2 小时")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text("唤醒时长")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(options, id: \.value) { option in
                    Button { minutes = option.value } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: minutes == option.value ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(minutes == option.value ? Color.accentColor : Color.secondary)
                            .background {
                                if minutes == option.value {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.value == 0 ? "持续唤醒，直到手动关闭" : "唤醒 \(option.title)")
                    .accessibilityAddTraits(minutes == option.value ? [.isSelected] : [])
                }
            }
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
