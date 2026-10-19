import SwiftUI

// No @State here: with only the Command Line Tools, SwiftUI's @State macro plugin isn't available.
struct SettingsView: View {
    let loginItem: LoginItem
    @AppStorage(Wheel.convert.settingsKey) private var convertKey = Wheel.convert.defaultModifier
    @AppStorage(Wheel.actions.settingsKey) private var actionsKey = Wheel.actions.defaultModifier

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))
                if loginItem.needsApproval {
                    LabeledContent("Allow Clementine under Login Items in System Settings.") {
                        Button("Open") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.error {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Tap while dragging to open") {
                ForEach(Wheel.allCases, id: \.self) { wheel in
                    Picker("\(wheel.title) wheel", selection: key(for: wheel)) {
                        ForEach(ModifierKey.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            Section {
                LabeledContent("Version", value: Self.version)
                Link("Clementine on GitHub", destination: URL(string: "https://github.com/seppedelanghe/Clementine")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
        .onAppear { loginItem.refresh() }
    }

    // "0.1.1 (2)": the build number is what Sparkle compares.
    private static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        return "\(version) (\(build))"
    }

    // Both wheels on one key would leave one unreachable, so picking the other wheel's key swaps them.
    private func key(for wheel: Wheel) -> Binding<ModifierKey> {
        Binding(
            get: { wheel == .convert ? convertKey : actionsKey },
            set: { newKey in
                switch wheel {
                case .convert:
                    if newKey == actionsKey { actionsKey = convertKey }
                    convertKey = newKey
                case .actions:
                    if newKey == convertKey { convertKey = actionsKey }
                    actionsKey = newKey
                }
            }
        )
    }
}
