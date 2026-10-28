import SwiftUI

struct SceneSwitcher: View {
    @ObservedObject var scenes: ScenePanel

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(scenes.scenes) { scene in
                        let selected = scenes.current.id == scene.id
                        Button { scenes.select(scene.id) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: scene.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                Text(scene.name.isEmpty ? "未命名" : scene.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 76, height: 32)
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("切换到\(scene.name.isEmpty ? "未命名" : scene.name)场景")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .help(scene.name.isEmpty ? "未命名场景" : scene.name)
                        .id(scene.id)
                    }
                }.padding(4)
            }
            .frame(height: 40)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .onAppear { reader.scrollTo(scenes.current.id, anchor: .center) }
            .onChange(of: scenes.current.id) { id in reader.scrollTo(id, anchor: .center) }
        }
    }
}
