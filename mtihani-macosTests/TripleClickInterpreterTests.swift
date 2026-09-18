import XCTest

@testable import mtihani_macos

final class TripleClickInterpreterTests: XCTestCase {
    func testSixClickSequenceTriggersOnlyOnceAtThresholdThree() {
        let interpreter = TripleClickInterpreter()
        XCTAssertEqual((1...6).filter { interpreter.isTrigger(button: .left, clickCount: $0) }, [3])
    }
    func testExactlyThreeLeftClicksTriggerCapture() {
        let interpreter = TripleClickInterpreter()

        XCTAssertTrue(interpreter.isTrigger(button: .left, clickCount: 3))
    }

    func testSingleDoubleAndFourthClicksDoNotTriggerCapture() {
        let interpreter = TripleClickInterpreter()

        XCTAssertFalse(interpreter.isTrigger(button: .left, clickCount: 1))
        XCTAssertFalse(interpreter.isTrigger(button: .left, clickCount: 2))
        XCTAssertFalse(interpreter.isTrigger(button: .left, clickCount: 4))
    }

    func testNonLeftClickNeverTriggersCapture() {
        let interpreter = TripleClickInterpreter()

        XCTAssertFalse(interpreter.isTrigger(button: .other, clickCount: 3))
    }

    func testConfiguredClickCountTriggersCapture() {
        let interpreter = TripleClickInterpreter(requiredClickCount: 4)

        XCTAssertFalse(interpreter.isTrigger(button: .left, clickCount: 3))
        XCTAssertTrue(interpreter.isTrigger(button: .left, clickCount: 4))
    }
}
