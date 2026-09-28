@testable import GhosttyTerminal
import Testing

struct TerminalKeyRepeatTests {
    /// HID usages: A, Delete, Return, Space, Left Arrow, Up Arrow, F5.
    @Test(arguments: [0x04, 0x2A, 0x28, 0x2C, 0x50, 0x52, 0x3E] as [UInt16])
    func `typing and navigation keys repeat`(usage: UInt16) {
        #expect(TerminalKeyRepeat.repeats(usage: usage, isCommandModified: false, isKeyCommand: false))
    }

    /// Caps Lock and Left/Right Control, Shift, Option, Command.
    @Test(arguments: [0x39, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7] as [UInt16])
    func `modifiers never repeat`(usage: UInt16) {
        #expect(TerminalKeyRepeat.isModifier(usage: usage))
        #expect(!TerminalKeyRepeat.repeats(usage: usage, isCommandModified: false, isKeyCommand: false))
    }

    @Test
    func `usages beside the modifier block are not modifiers`() {
        #expect(!TerminalKeyRepeat.isModifier(usage: 0xDF))
        #expect(!TerminalKeyRepeat.isModifier(usage: 0xE8))
        #expect(!TerminalKeyRepeat.isModifier(usage: 0x3A))
    }

    @Test
    func `command combos do not repeat`() {
        #expect(!TerminalKeyRepeat.repeats(usage: 0x2E, isCommandModified: true, isKeyCommand: false))
    }

    /// Ctrl+C and Escape arrive through a `UIKeyCommand`. On a system that
    /// also delivers the press, repeating it would double the command.
    @Test
    func `keys owned by a key command do not repeat`() {
        #expect(!TerminalKeyRepeat.repeats(usage: 0x06, isCommandModified: false, isKeyCommand: true))
        #expect(!TerminalKeyRepeat.repeats(usage: 0x29, isCommandModified: false, isKeyCommand: true))
    }
}
