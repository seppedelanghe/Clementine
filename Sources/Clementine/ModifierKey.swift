import AppKit

enum ModifierKey: String, CaseIterable, Identifiable {
    case shift
    case control
    case option
    case command

    var id: Self { self }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }

    var title: String {
        switch self {
        case .shift: "⇧ Shift"
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .command: "⌘ Command"
        }
    }
}

extension Wheel {
    var title: String {
        switch self {
        case .convert: "Convert"
        case .actions: "Actions"
        }
    }

    var settingsKey: String {
        switch self {
        case .convert: "convertModifier"
        case .actions: "actionsModifier"
        }
    }

    var defaultModifier: ModifierKey {
        switch self {
        case .convert: .shift
        case .actions: .control
        }
    }

    var modifier: ModifierKey {
        UserDefaults.standard.string(forKey: settingsKey).flatMap(ModifierKey.init(rawValue:)) ?? defaultModifier
    }
}
