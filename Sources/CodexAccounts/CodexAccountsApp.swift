import SwiftUI
import AppKit

@main struct CodexAccountsApp: App {
    @StateObject private var model = AppModel(demo: PreviewConfiguration.enabled)
    var body: some Scene {
        WindowGroup("Codex Accounts", id: "accounts") {
            AccountsView().environmentObject(model)
                .frame(minWidth: 820, minHeight: 590)
                .preferredColorScheme(model.preferredColorScheme)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("浏览器添加账号…") { model.addViaLogin() }.keyboardShortcut("n").disabled(model.busy || model.demo)
            }
        }
        MenuBarExtra {
            MenuPanel().environmentObject(model).preferredColorScheme(model.preferredColorScheme)
        } label: {
            Image(nsImage: SwitchGlyph.menuBarImage).accessibilityLabel("Codex Accounts 快速切换")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().environmentObject(model).preferredColorScheme(model.preferredColorScheme).frame(width: 540) }
        Window("快速切换", id: "menu-preview") {
            MenuPanel().environmentObject(model).preferredColorScheme(model.preferredColorScheme)
        }.windowResizability(.contentSize)
    }
}
