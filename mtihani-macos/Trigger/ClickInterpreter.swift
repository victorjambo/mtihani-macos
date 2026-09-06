//
//  ClickInterpreter.swift
//  mtihani-macos
//

import Foundation

/// The mouse button represented by an input event.
///
/// Keeping this type independent of AppKit lets trigger behavior be tested
/// without constructing or posting system events.
nonisolated enum ClickButton: Equatable, Sendable {
    case left
    case other
}

/// Interprets click metadata without retaining any sequence state.
///
/// macOS already calculates a click count using the user's configured timing
/// and pointer-location tolerances. The interpreter deliberately trusts that
/// native value instead of attempting to reconstruct a click sequence.
nonisolated struct TripleClickInterpreter: Sendable {
    let requiredClickCount: Int

    init(requiredClickCount: Int = 3) {
        precondition(requiredClickCount > 0, "The required click count must be positive.")
        self.requiredClickCount = requiredClickCount
    }

    nonisolated func isTrigger(button: ClickButton, clickCount: Int) -> Bool {
        button == .left && clickCount == requiredClickCount
    }
}
