import SwiftUI

struct HaloDockTheme: ViewModifier {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("accent") private var accent = "coral"

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .tint(accentColor)
            .accentColor(accentColor)
    }

    private var accentColor: Color {
        switch accent {
        case "blue": return Color(red: 0.18, green: 0.40, blue: 0.85)
        case "green": return Color(red: 0.12, green: 0.58, blue: 0.38)
        default: return Color(red: 0.95, green: 0.33, blue: 0.20)
        }
    }
}

extension Color {
    static let haloOrange = Color(red: 0.95, green: 0.33, blue: 0.20)
    static let haloGreen = Color(red: 0.12, green: 0.58, blue: 0.38)
    static let haloBlue = Color(red: 0.18, green: 0.40, blue: 0.85)
}
