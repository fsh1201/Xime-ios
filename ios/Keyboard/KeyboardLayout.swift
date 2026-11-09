import Foundation

enum KeyboardLayer: String, Equatable {
    case letters
    case numbers
    case symbols
}

enum KeyAction: Equatable {
    case character(Character)
    case shift
    case delete
    case space
    case returnKey
    case globe
    case layer(KeyboardLayer)
    case none
}

struct KeyboardKey: Identifiable, Equatable {
    let id: String
    let label: String
    let systemImage: String?
    let action: KeyAction
    let width: Double
    let isSpecial: Bool

    init(
        _ id: String,
        label: String = "",
        systemImage: String? = nil,
        action: KeyAction,
        width: Double = 1.0,
        isSpecial: Bool = false
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.action = action
        self.width = width
        self.isSpecial = isSpecial
    }
}

enum KeyboardLayout {
    static func rows(for layer: KeyboardLayer, shifted: Bool, showsGlobe: Bool = true) -> [[KeyboardKey]] {
        switch layer {
        case .letters:
            return letterRows(shifted: shifted, showsGlobe: showsGlobe)
        case .numbers:
            return numberRows(showsGlobe: showsGlobe)
        case .symbols:
            return symbolRows(showsGlobe: showsGlobe)
        }
    }

    private static func letterRows(shifted: Bool, showsGlobe: Bool) -> [[KeyboardKey]] {
        let rows = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]

        let first = rows[0].map { characterKey($0, shifted: shifted) }
        var second = rows[1].map { characterKey($0, shifted: shifted) }
        second.insert(KeyboardKey("spacer-left", action: .none, width: 0.5), at: 0)
        second.append(KeyboardKey("spacer-right", action: .none, width: 0.5))

        var third = [
            KeyboardKey(
                "shift",
                systemImage: shifted ? "shift.fill" : "shift",
                action: .shift,
                width: 1.5,
                isSpecial: true
            )
        ]
        third.append(contentsOf: rows[2].map { characterKey($0, shifted: shifted) })
        third.append(
            KeyboardKey(
                "delete",
                systemImage: "delete.left",
                action: .delete,
                width: 1.5,
                isSpecial: true
            )
        )

        return [first, second, third, bottomRow(leading: ("123", .layer(.numbers)), showsGlobe: showsGlobe)]
    }

    private static func numberRows(showsGlobe: Bool) -> [[KeyboardKey]] {
        let first = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            .map { characterKey($0) }
        let second = ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""]
            .map { characterKey($0) }

        var third = [
            KeyboardKey(
                "symbols",
                label: "#+=",
                action: .layer(.symbols),
                width: 1.5,
                isSpecial: true
            )
        ]
        third.append(contentsOf: [".", ",", "?", "!", "'"].map { characterKey($0) })
        third.append(
            KeyboardKey(
                "delete",
                systemImage: "delete.left",
                action: .delete,
                width: 1.5,
                isSpecial: true
            )
        )

        return [first, second, third, bottomRow(leading: ("ABC", .layer(.letters)), showsGlobe: showsGlobe)]
    }

    private static func symbolRows(showsGlobe: Bool) -> [[KeyboardKey]] {
        let first = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            .map { characterKey($0) }
        let second = ["_", "\\", "|", "~", "<", ">", "€", "£", "•", "·"]
            .map { characterKey($0) }

        var third = [
            KeyboardKey(
                "numbers",
                label: "123",
                action: .layer(.numbers),
                width: 1.5,
                isSpecial: true
            )
        ]
        third.append(contentsOf: ["\"", "'", ",", ".", "?"].map { characterKey($0) })
        third.append(
            KeyboardKey(
                "delete",
                systemImage: "delete.left",
                action: .delete,
                width: 1.5,
                isSpecial: true
            )
        )

        return [first, second, third, bottomRow(leading: ("ABC", .layer(.letters)), showsGlobe: showsGlobe)]
    }

    private static func bottomRow(leading: (String, KeyAction), showsGlobe: Bool) -> [KeyboardKey] {
        var row = [
            KeyboardKey("layer", label: leading.0, action: leading.1, width: 1.25, isSpecial: true)
        ]
        if showsGlobe {
            row.append(
                KeyboardKey("globe", systemImage: "globe", action: .globe, width: 1.25, isSpecial: true)
            )
        }
        row.append(KeyboardKey("space", label: "空格", action: .space, width: 5.5))
        row.append(KeyboardKey("return", label: "换行", action: .returnKey, width: 2.0, isSpecial: true))
        return row
    }

    private static func characterKey(_ value: String, shifted: Bool = false) -> KeyboardKey {
        let character = Character(shifted ? value.uppercased() : value)
        return KeyboardKey(
            "key-\(value)",
            label: String(character),
            action: .character(character)
        )
    }
}
