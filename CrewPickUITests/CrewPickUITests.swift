import XCTest

@MainActor
final class CrewPickUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(extraArguments: [String] = []) {
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launchArguments += extraArguments
        app.launch()
    }

    func testBrowseReactAndComment() throws {
        launch()
        let group = app.descendants(matching: .any)["group-card-10000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()

        let idea = app.descendants(matching: .any)["idea-card-20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(idea.waitForExistence(timeout: 5))
        idea.tap()

        let title = app.staticTexts["idea-detail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, "Bar Raval")

        let comment = app.textFields["comment-field"]
        XCTAssertTrue(comment.waitForExistence(timeout: 3))
        comment.tap()
        comment.typeText("Friday works")
        app.buttons["post-comment"].tap()
        XCTAssertTrue(app.staticTexts["Friday works"].waitForExistence(timeout: 3))
    }

    func testAddIdeaToBoard() throws {
        launch()
        let group = app.descendants(matching: .any)["group-card-10000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()

        let addButton = app.buttons["Add idea"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        app.buttons["Top ranked"].tap()
        addButton.tap()

        let title = app.textFields["idea-title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Sunset picnic")
        app.buttons["Post"].tap()

        let savedIdea = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sunset picnic")).firstMatch
        XCTAssertTrue(savedIdea.waitForExistence(timeout: 3))
    }

    func testBoardAtAccessibilityTextSizeInDarkMode() throws {
        launch(extraArguments: [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])

        let group = app.descendants(matching: .any)["group-card-10000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()
        XCTAssertTrue(app.buttons["Add idea"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Decide for us"].exists)
    }
}
