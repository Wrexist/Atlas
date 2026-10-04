import XCTest

/// Captures full-screen screenshots of every main surface so a PR can show
/// real before/after app captures (not code renders).
///
/// Boots the app in **ScreenshotMode** — the app's polished demo-data state
/// — via launch arguments, so every tab is populated and deterministic.
/// Each capture is attached with `.keepAlways` so it survives into the
/// `.xcresult`, which the `screenshots` workflow exports as PNGs.
///
/// Three passes, because the two most recent design changes are invisible to
/// a single default-appearance run:
///
/// - **Dark, default type** — the appearance the app shipped with.
/// - **Light** — every `AppColor` surface and ink token became
///   trait-resolving, and no screen had ever been rendered in light mode.
/// - **Accessibility XXXL** — 393 call sites moved onto a six-step type
///   scale, and `AppFont.scaled` routes through `UIFontMetrics`; the largest
///   content-size category is where truncation would show up.
///
/// Opt-in only: run via the dedicated `Screenshots` workflow (or the
/// `run-ui-tests` label). See `.github/workflows/screenshots.yml`.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    /// Tab bar buttons in display order. Today is the launch tab, so it's
    /// captured before any tap.
    private static let secondaryTabs = ["Train", "Meals", "Biology", "Library"]

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Passes

    func test_captureWorkoutSocialSharing() {
        openCompletedFixture(appearance: "dark")
        app.buttons["Share workout"].tap()
        XCTAssertTrue(app.navigationBars["Share workout"].waitForExistence(timeout: 10))
        for style in [("Exercise highlight", "highlight"), ("Dark summary", "summary")] {
            scrollToTop()
            app.segmentedControls["workout-share-style"].buttons[style.0].tap()
            for format in [("Story", "story"), ("Post", "post"), ("Reel", "reel")] {
                scrollToTop()
                app.segmentedControls["workout-share-format"].buttons[format.0].tap()
                XCTAssertTrue(app.images["workout-share-rendered-\(style.1)-\(format.1)"].waitForExistence(timeout: 10))
                capture(named: "social-\(style.1)-\(format.1)")
            }
        }
        app.buttons["workout-share-preview-video"].tap()
        XCTAssertTrue(app.otherElements["workout-share-video-player"].waitForExistence(timeout: 90))
        capture(named: "social-reel-video-preview")
        app.buttons["workout-share-send"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 20))
        capture(named: "social-native-share-sheet")
        app.swipeDown()
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["recap-done"].waitForExistence(timeout: 5))
    }

    func test_captureWorkoutCompletion() {
        openCompletedFixture(appearance: "dark")
        capture(named: "completion-01-summary")
        app.buttons["Edit"].tap()
        let name = app.textFields["Workout name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(" reviewed")
        app.buttons["save-workout-edits"].tap()
        XCTAssertTrue(app.staticTexts["Push Workout reviewed"].waitForExistence(timeout: 5))
        let exercises = app.buttons["recap-exercises"]
        reveal(exercises)
        exercises.tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
        capture(named: "completion-03-exercises")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let muscles = app.buttons["recap-muscles"]
        reveal(muscles)
        muscles.tap()
        XCTAssertTrue(app.navigationBars["Muscle details"].waitForExistence(timeout: 5))
        capture(named: "completion-02-muscle-map")
        app.segmentedControls.buttons["Muscle list"].tap()
        capture(named: "completion-02b-muscle-list")
        let triceps = app.buttons["recap-muscle-triceps"]
        reveal(triceps)
        triceps.tap()
        XCTAssertTrue(app.navigationBars["Triceps"].waitForExistence(timeout: 5))
        capture(named: "completion-02c-contributions")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollToTop()
        app.buttons["recap-weekly"].tap()
        XCTAssertTrue(app.navigationBars["This week"].waitForExistence(timeout: 5))
        capture(named: "completion-07-weekly")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Share workout"].tap()
        XCTAssertTrue(app.navigationBars["Share workout"].waitForExistence(timeout: 5))
        capture(named: "completion-08-share-preview")
        let share = app.buttons["Share"].firstMatch
        reveal(share)
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        app.swipeDown()
        app.buttons["Close"].firstMatch.tap()
        app.buttons["recap-done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Train"].waitForExistence(timeout: 5))
    }

    func test_captureWorkoutCompletionLayouts() {
        for appearance in ["light", "dark"] {
            openCompletedFixture(appearance: appearance, arguments: appearance == "dark" ? [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--completion-long-name"
            ] : [])
            XCTAssertTrue(app.buttons["recap-done"].isHittable)
            capture(named: "completion-layout-\(appearance)")
            let muscles = app.buttons["recap-muscles"]
            reveal(muscles)
            XCTAssertTrue(muscles.isHittable)
            capture(named: "completion-layout-\(appearance)-scrolled")
            app.buttons["recap-done"].tap()
            app.terminate()
        }
    }

    func test_captureWorkoutCompletionEditValidation() {
        openCompletedFixture(appearance: "dark")
        app.buttons["Edit"].tap()
        let firstSet = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recap-edit-set-")).firstMatch
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        let load = app.textFields["Load (lb)"].firstMatch
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        load.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        let save = app.buttons["save-workout-edits"]
        XCTAssertFalse(save.isEnabled, "An empty field must not silently save its previous value")
        capture(named: "completion-editor-invalid-input")
        load.typeText("100")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        XCTAssertEqual(load.value as? String, "100")
        app.buttons["Cancel"].tap()
        app.buttons["recap-done"].tap()
    }

    func test_captureWorkoutCompletionSaveError() {
        launch(appearance: "dark", extraArguments: ["--completion-fixture", "--completion-save-failure"])
        dismissOverlaysIfNeeded()
        app.tabBars.buttons["Train"].tap()
        let options = app.buttons["workout-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        app.buttons["Finish workout"].firstMatch.tap()
        let finish = app.buttons["confirm-finish-workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        reveal(finish)
        finish.tap()
        XCTAssertTrue(app.navigationBars["Save error"].waitForExistence(timeout: 10))
        capture(named: "completion-05-real-save-error")
        XCTAssertFalse(app.staticTexts["Workout saved"].exists)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 10))
        capture(named: "completion-05b-retry-success")
        app.buttons["recap-done"].tap()
    }

    private func openCompletedFixture(appearance: String, arguments: [String] = []) {
        launch(appearance: appearance, extraArguments: ["--completion-fixture"] + arguments)
        dismissOverlaysIfNeeded()
        app.tabBars.buttons["Train"].tap()
        let options = app.buttons["workout-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        app.buttons["Finish workout"].firstMatch.tap()
        let finish = app.buttons["confirm-finish-workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        reveal(finish)
        finish.tap()
        XCTAssertTrue(app.staticTexts["Workout saved"].waitForExistence(timeout: 15))
    }

    func test_captureAllTabs() {
        launch(appearance: "dark")
        captureAllTabs(prefix: "dark")
    }

    /// Light mode is driven through the app's own `appDisplayMode` default —
    /// the same key `ThemeManager` reads — rather than the simulator's
    /// appearance, because that's the switch a user actually flips.
    func test_captureAllTabs_lightMode() {
        launch(appearance: "light")
        captureAllTabs(prefix: "light")
    }

    /// Largest accessibility content-size category. Anything that truncates,
    /// clips, or overlaps at this size is a layout bug, not a preference.
    func test_captureAllTabs_accessibilityTextSize() {
        launch(
            appearance: "dark",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        captureAllTabs(prefix: "xxxl")
    }

    /// Real app navigation and set edits, captured on the remote iOS simulator.
    func test_captureWorkoutFocus() {
        for appearance in ["light", "dark"] {
            launch(appearance: appearance)
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
            dismissOverlaysIfNeeded()
            let train = app.tabBars.buttons["Train"]
            XCTAssertTrue(train.waitForExistence(timeout: 10))
            train.tap()
            dismissOverlaysIfNeeded()
            let start = app.buttons["Start workout"]
            reveal(start)
            start.tap()
            let add = app.buttons["Add exercise"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("Incline Dumbbell Press")
            let exercise = app.staticTexts["Incline Dumbbell Press"].firstMatch
            XCTAssertTrue(exercise.waitForExistence(timeout: 10))
            exercise.tap()
            let commit = app.buttons["Add (1)"]
            XCTAssertTrue(commit.waitForExistence(timeout: 5))
            commit.tap()
            let addSet = app.buttons["Add set"]
            XCTAssertTrue(addSet.waitForExistence(timeout: 10))
            for _ in 0..<3 { reveal(addSet); addSet.tap() }
            for index in 1...4 {
                replaceField("workout-weight-\(index)", with: index <= 2 ? "22.5" : "25")
                replaceField("workout-reps-\(index)", with: index <= 2 ? "10" : "8")
            }
            let first = app.buttons["workout-complete-1"]
            reveal(first)
            first.tap()
            let skip = app.buttons["Skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            let undo = app.buttons["workout-undo-rest-set"]
            reveal(undo)
            undo.tap()
            XCTAssertFalse(skip.exists)
            reveal(first)
            first.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            reveal(skip)
            skip.tap()
            scrollToTop()
            capture(named: "incline-\(appearance)-01-logging")

            let second = app.buttons["workout-complete-2"]
            reveal(second)
            second.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            scrollToTop()
            capture(named: "incline-\(appearance)-02-rest")

            app.buttons["Pause workout"].tap()
            capture(named: "incline-\(appearance)-03-paused")
            app.buttons["Workout options"].tap()
            app.buttons["Discard workout"].tap()
            app.alerts.buttons["Discard"].tap()
            app.terminate()
        }
    }

    func test_capturePremiumTrainingContinuity() {
        launch(appearance: "dark")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        dismissOverlaysIfNeeded()
        app.tabBars.buttons["Train"].tap()
        dismissOverlaysIfNeeded()
        app.buttons["Exercises"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Incline Dumbbell Press")
        let exercise = app.staticTexts["Incline Dumbbell Press"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10))
        capture(named: "premium-01-library")
        exercise.tap()
        capture(named: "premium-02-exercise-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Routines"].firstMatch.tap()
        app.buttons["Exercises"].firstMatch.tap()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Incline Dumbbell Press")
        XCTAssertTrue(exercise.exists)
        capture(named: "premium-03-restored-search")
        app.buttons["Overview"].firstMatch.tap()
        scrollToTop()
        capture(named: "premium-04-overview")
        let trends = app.buttons["training-trends-disclosure"]
        reveal(trends)
        trends.tap()
        capture(named: "premium-05-training-trends")
    }

    func test_captureExerciseRollout() {
        test_captureWorkoutFocus()
        for appearance in ["light", "dark"] {
            launch(appearance: appearance)
            dismissOverlaysIfNeeded()
            app.tabBars.buttons["Train"].tap()
            dismissOverlaysIfNeeded()
            let start = app.buttons["Start workout"]
            reveal(start)
            start.tap()
            for name in ["Barbell Full Squat", "Dumbbell Bicep Curl", "Pullups", "90/90 Hamstring"] {
                let add = app.buttons["Add exercise"].firstMatch
                reveal(add)
                add.tap()
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.waitForExistence(timeout: 10))
                search.tap()
                search.typeText(name)
                let result = app.staticTexts[name].firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 10))
                result.tap()
                app.buttons["Add (1)"].tap()
                XCTAssertTrue(app.buttons["Add set"].waitForExistence(timeout: 10))
                scrollToTop()
                capture(named: "catalog-\(appearance)-\(name.replacingOccurrences(of: "/", with: "-"))")
            }
            app.buttons["Workout options"].tap()
            app.buttons["Discard workout"].tap()
            app.alerts.buttons["Discard"].tap()
            app.terminate()
        }
    }

    func test_captureMuscleTraining() {
        for appearance in ["light", "dark"] {
            launch(appearance: appearance)
            dismissOverlaysIfNeeded()
            let train = app.tabBars.buttons["Train"]
            XCTAssertTrue(train.waitForExistence(timeout: 10))
            train.tap()
            dismissOverlaysIfNeeded()
            if !train.isSelected { train.tap() }
            XCTAssertTrue(train.isSelected)
            let period = app.segmentedControls["training-map-period"]
            XCTAssertTrue(period.waitForExistence(timeout: 10))
            period.buttons["Today"].tap()
            capture(named: "body-\(appearance)-01-today")
            period.buttons["30 days"].tap()
            capture(named: "body-\(appearance)-02-month")
            let start = app.buttons["Start workout"]
            reveal(start)
            start.tap()
            let add = app.buttons["Add exercise"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            search.typeText("Incline Dumbbell Press")
            let exercise = app.staticTexts["Incline Dumbbell Press"].firstMatch
            XCTAssertTrue(exercise.waitForExistence(timeout: 10))
            exercise.tap()
            app.buttons["Add (1)"].tap()
            replaceField("workout-weight-1", with: "22.5")
            replaceField("workout-reps-1", with: "10")
            let complete = app.buttons["workout-complete-1"]
            reveal(complete)
            complete.tap()
            app.buttons["workout-options"].tap()
            app.buttons["Workout overview"].tap()
            XCTAssertTrue(app.staticTexts["Muscles trained"].waitForExistence(timeout: 10))
            capture(named: "body-\(appearance)-03-session")
            let bodySide = app.segmentedControls["training-body-side"].firstMatch
            reveal(bodySide)
            bodySide.buttons["Front"].tap()
            XCTAssertTrue(bodySide.buttons["Front"].isSelected)
            capture(named: "body-\(appearance)-03a-front")
            bodySide.buttons["Back"].tap()
            XCTAssertTrue(bodySide.buttons["Back"].isSelected)
            capture(named: "body-\(appearance)-03b-back")
            bodySide.buttons["Both"].tap()
            let explore = app.buttons["explore-trained-muscles"]
            reveal(explore)
            explore.tap()
            app.buttons["Upper chest"].firstMatch.tap()
            let selectedHistory = app.buttons["selected-muscle-history"]
            reveal(selectedHistory)
            capture(named: "body-\(appearance)-03c-selected")
            selectedHistory.tap()
            XCTAssertTrue(app.staticTexts["Incline Dumbbell Press"].firstMatch.waitForExistence(timeout: 5))
            capture(named: "body-\(appearance)-04-muscle-history")
            app.buttons["muscle-history-done"].tap()
            let overviewDone = app.buttons["workout-overview-done"]
            XCTAssertTrue(overviewDone.waitForExistence(timeout: 5))
            overviewDone.tap()
            // The completed exercise exposes a direct finish action.
            app.buttons["Finish workout"].firstMatch.tap()
            let finish = app.buttons["confirm-finish-workout"]
            XCTAssertTrue(finish.waitForExistence(timeout: 10))
            // The optional effort/note form can put Save below the medium
            // sheet's fold. Scroll inside the visible sheet before tapping.
            app.swipeUp()
            finish.tap()
            XCTAssertTrue(app.staticTexts["Workout saved"].firstMatch.waitForExistence(timeout: 10))
            let summaryDone = app.buttons["recap-done"]
            XCTAssertTrue(summaryDone.waitForExistence(timeout: 5))
            capture(named: "body-\(appearance)-05-completed")
            summaryDone.tap()
            dismissOverlaysIfNeeded()
            scrollToTop()
            capture(named: "body-\(appearance)-06-training-history")
            app.terminate()
        }
    }

    private func replaceField(_ identifier: String, with value: String) {
        let field = app.textFields[identifier]
        reveal(field)
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        } else {
            // Numeric fields can select their entire single token on double tap.
            field.doubleTap()
        }
        field.typeText(value)
        app.buttons["Done"].firstMatch.tap()
        let stored = (field.value as? String ?? "").replacingOccurrences(of: " reps", with: "")
        XCTAssertTrue(stored == value || stored.hasPrefix(value + " "), "Expected \(value), found \(stored)")
    }

    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        // Keyboard dismissal can leave earlier rows above the viewport. Start
        // from the top before searching downward, rather than swiping those
        // rows farther offscreen on every attempt.
        if !element.isHittable { scrollToTop() }
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func scrollToTop() {
        for _ in 0..<3 { app.swipeDown() }
    }

    // MARK: - Helpers

    private func launch(appearance: String, extraArguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-key value` pairs land in the NSArgumentDomain, so these read
        // back through UserDefaults at launch: skip onboarding, flip
        // ScreenshotMode on (its key is read by ScreenshotMode.init), and
        // pin the appearance (read by ThemeManager.init).
        //
        // Also pre-stamp WhatsNewService's "last seen tour version" key
        // (`WhatsNewService.currentTourVersion`, currently "v3.1-biology").
        // `bootstrapForFreshInstallIfNeeded` only stamps this on launch when
        // `hasCompletedOnboarding` is still false, but this suite launches
        // with onboarding pre-completed above — so on a fresh simulator the
        // stamp is never written, `shouldShowTour` sees a nil last-seen
        // version, and PeptideApp presents the full-screen, drag-to-dismiss-
        // disabled WhatsNewTourSheet ~450ms after the first `.active` scene
        // phase. That sheet then silently absorbs every subsequent tab tap
        // in `captureAllTabs` (each tap lands on the sheet's own "Continue"
        // control, which happens to sit in the same screen region as the
        // real tab bar), so every capture past the first ends up showing a
        // tour page instead of the tab it's named after, and the Library
        // tab / paywall step are never reached. Stamping the key up front
        // matches how a real existing user (the only audience this tour
        // targets) would already have it set, and keeps the suite in sync
        // if `currentTourVersion` is bumped again.
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-com.peptidesai.app.screenshotMode.enabled", "YES",
            "-appDisplayMode", appearance,
            "-com.peptidesai.app.whatsNew.lastSeenVersion", "v3.1-biology",
        ] + extraArguments
        app.launch()
    }

    /// Walks the five tabs and captures each. Tabs that don't appear are
    /// skipped rather than failing, so one renamed tab can't lose the
    /// whole run. The Biology tab additionally opens the paywall — see
    /// `capturePaywall`.
    ///
    /// Two different first-launch overlays can appear at any point in
    /// this sequence, neither gated on a specific screen:
    ///
    /// - The system notification-permission alert.
    /// - `HomeView`'s `CycleMilestonePromptSheet` ("Share your week 1
    ///   snapshot?"), triggered by `CycleMilestoneService` once the demo
    ///   protocol's seeded start date crosses the day-7 mark. It's a
    ///   `.sheet`, not an `.alert`, and its "Not now" `GlassButton` sits
    ///   low enough on screen to overlap the tab bar.
    ///
    /// Left unhandled, either one silently absorbs the *next* tap instead
    /// of blocking it (the control underneath still receives touches, or
    /// the tap lands on the overlay's own button by screen-position
    /// coincidence), so a tab switch silently no-ops or the overlay
    /// dismisses one tap later than expected — pushing every subsequent
    /// screenshot's label out of sync with what's actually on screen, and
    /// dropping the last tab (and the paywall step) off the end entirely.
    /// `dismissOverlaysIfNeeded()` clears both before they can do that.
    private func captureAllTabs(prefix: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        dismissOverlaysIfNeeded()
        capture(named: "\(prefix)-01-Today")

        for (offset, tab) in Self.secondaryTabs.enumerated() {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            dismissOverlaysIfNeeded()
            capture(named: String(format: "%@-%02d-%@", prefix, offset + 2, tab))

            if tab == "Biology" {
                capturePaywall(prefix: prefix, slot: offset + 3)
            }
        }
    }

    /// Dismisses whichever first-launch overlay (if any) is currently on
    /// screen — see `captureAllTabs`'s doc comment for why both need
    /// clearing before every capture. Cheap to call speculatively: each
    /// wait only costs real time when that overlay is actually present.
    private func dismissOverlaysIfNeeded() {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 0.5) {
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
            } else if alert.buttons["Don't Allow"].exists {
                alert.buttons["Don't Allow"].tap()
            }
        }

        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 0.5) {
            notNow.tap()
        }
        // On compact phones the demo reminder overlaps the tab bar. Hide
        // only the reminder; tapping its main body would exit demo mode.
        let hideReminder = app.buttons["Hide screenshot mode reminder"]
        if hideReminder.waitForExistence(timeout: 0.5) {
            hideReminder.tap()
        }
    }

    /// The paywall (App Store screenshot slot 8). Demo mode always renders
    /// Bio Age locked — `ScreenshotMode` seeds no HealthKit history — so
    /// `BioAgeHeroSection`'s "Unlock with Pro" pill is on screen right
    /// after the Biology capture above. Its `accessibilityLabel` is
    /// "Unlock biological age with Pro" (`BioAgeHeroSection.unlockPill`);
    /// tapping it calls `BiologyView.presentPaywall()`, which presents
    /// `PaywallView` as a sheet.
    ///
    /// `PaywallView`'s `.task` awaits `StoreService.loadProducts()` before
    /// the pricing rows render. The `PeptideUICapture` scheme wires
    /// `Peptide/Resources/Products.storekit` as its test action's
    /// `storeKitConfiguration` (see `project.yml`), so the three real
    /// product IDs resolve locally, in-process, with no network or
    /// sandbox account — the sleep below just gives that local resolution
    /// (and the async trial-eligibility check that follows it) time to
    /// land before the capture.
    ///
    /// Skips rather than fails if the button or the sheet doesn't show,
    /// matching `captureAllTabs`'s per-tab tolerance: a renamed control on
    /// this one screen shouldn't fail the whole capture run.
    private func capturePaywall(prefix: String, slot: Int) {
        let unlockButton = app.buttons["Unlock biological age with Pro"]
        guard unlockButton.waitForExistence(timeout: 5) else { return }
        unlockButton.tap()

        let closeButton = app.buttons["Close"]
        guard closeButton.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 2.0)
        dismissOverlaysIfNeeded()
        capture(named: String(format: "%@-%02d-Paywall", prefix, slot))

        // Dismiss so the loop above can go on to try the Library tab.
        closeButton.tap()
    }

    private func capture(named name: String) {
        // Let the screen settle past its appear animation before grabbing.
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
