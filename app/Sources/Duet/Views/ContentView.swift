import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("duet.language") private var languageRaw = AppLanguage.systemDefault.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .systemDefault
    }

    var body: some View {
        let palette = DuetPalette.forTheme(store.theme)

        VStack(spacing: 0) {
            ToolbarView()
            HStack(spacing: 0) {
                SidebarView()
                RoomView()
            }
            InjectView()
        }
        .background(palette.window)
        .environment(\.duetPalette, palette)
        .environment(\.appLanguage, language)
        .preferredColorScheme(store.theme == .light ? .light : .dark)
    }
}
