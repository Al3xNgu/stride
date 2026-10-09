import XCTest

final class StrideUITests: XCTestCase {
    @MainActor
    func testBuildSaveAndSendWorkoutToWatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-StrideUITestMode"]
        app.launch()

        let newWorkout = app.buttons["library.newWorkout"]
        XCTAssertTrue(newWorkout.waitForExistence(timeout: 5))
        newWorkout.tap()

        let name = app.textFields["builder.workoutName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI Test Workout")
        name.typeText("\n")

        app.buttons["builder.save"].tap()
        app.navigationBars["Builder"].buttons["Library"].tap()

        let workout = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "UI Test Workout")
        ).firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 3))
        workout.press(forDuration: 1)
        app.buttons["library.sendToWatchNow"].tap()

        XCTAssertTrue(app.staticTexts["On Watch"].waitForExistence(timeout: 5))
    }
}
