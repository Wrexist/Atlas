import XCTest
@testable import Peptide

@MainActor
final class WorkoutCSVExportTests: XCTestCase {

    private let header = "Date,Workout,Exercise,Set,Reps,Weight (kg),RPE,Measurement,Load,Seconds,Meters,Set Type,Superset,Duration (min),Set Note,Workout Note"
    private let stockholm = TimeZone(identifier: "Europe/Stockholm")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stockholm
        return calendar
    }

    private func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)))
    }

    private func csv(_ sessions: [WorkoutSession]) -> String {
        let names = ["bench": "Bench Press", "row": "Barbell Row", "squat": "Squat"]
        return ExportService.shared.exportWorkoutsCSV(
            sessions: sessions,
            exerciseName: { names[$0] ?? "Unknown exercise" },
            timeZone: stockholm
        )
    }

    private func rows(_ csv: String) -> [String] {
        csv.split(separator: "\n").dropFirst().map(String.init)
    }

    func test_emptyHistory_exportsHeaderOnly() {
        XCTAssertEqual(csv([]), header + "\n")
    }

    func test_finishedWorkout_writesOneRowPerCompletedSetWithWorkoutColumnsRepeated() throws {
        let start = try date(day: 14, hour: 18, minute: 30)
        let session = WorkoutSession(
            name: "Push",
            startedAt: start,
            finishedAt: start.addingTimeInterval(45 * 60),
            exercises: [
                WorkoutExerciseEntry(exerciseID: "bench", index: 0, sets: [
                    SetEntry(index: 1, weightKg: 40, reps: 10, completed: true, isWarmup: true),
                    SetEntry(index: 2, weightKg: 82.5, reps: 5, rpe: 8.5, completed: true),
                    SetEntry(index: 3, weightKg: 82.5, reps: 5, completed: false),
                ]),
            ],
            note: "Felt strong"
        )

        XCTAssertEqual(rows(csv([session])), [
            "2026-03-14T18:30:00+01:00,Push,Bench Press,1,10,40,,repetitions,recorded,,,Warm-up,,45,,Felt strong",
            "2026-03-14T18:30:00+01:00,Push,Bench Press,2,5,82.5,8.5,repetitions,recorded,,,Working,,45,,Felt strong",
        ])
    }

    func test_quickLoggedWorkoutWithoutSets_writesOneSessionRow() throws {
        let start = try date(day: 12, hour: 17)
        let session = WorkoutSession(
            name: "Run",
            startedAt: start,
            finishedAt: start.addingTimeInterval(20 * 60),
            exercises: [],
            note: "Quick-log · 3 sets × 10 reps"
        )

        XCTAssertEqual(rows(csv([session])), [
            "2026-03-12T17:00:00+01:00,Run,,,,,,,,,,,,20,,Quick-log · 3 sets × 10 reps",
        ])
    }

    func test_supersetWorkout_lettersMembersAndLeavesStandaloneEmpty() throws {
        let start = try date(day: 10, hour: 7)
        let group = UUID()
        let session = WorkoutSession(
            name: "Pull",
            startedAt: start,
            finishedAt: start.addingTimeInterval(30 * 60),
            exercises: [
                WorkoutExerciseEntry(exerciseID: "squat", index: 2, sets: [SetEntry(index: 1, weightKg: 100, reps: 3, completed: true)]),
                WorkoutExerciseEntry(exerciseID: "bench", index: 0, sets: [SetEntry(index: 1, weightKg: 60, reps: 8, completed: true)], supersetGroup: group),
                WorkoutExerciseEntry(exerciseID: "row", index: 1, sets: [SetEntry(index: 1, weightKg: 50, reps: 8, completed: true)], supersetGroup: group),
            ]
        )

        let fields = rows(csv([session])).map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(fields.map { $0[2] }, ["Bench Press", "Barbell Row", "Squat"])
        XCTAssertEqual(fields.map { $0[12] }, ["A", "A", ""])
    }

    func test_workoutsCSV_timedAndDistanceSets_exportSecondsAndMeters() throws {
        let start = try date(day: 15, hour: 8)
        let session = WorkoutSession(
            name: "Conditioning",
            startedAt: start,
            finishedAt: start.addingTimeInterval(30 * 60),
            exercises: [
                WorkoutExerciseEntry(exerciseID: "plank", index: 0, sets: [
                    SetEntry(index: 1, weightKg: 0, reps: 0, completed: true,
                             measurement: .init(kind: .timed, seconds: 60)),
                ]),
                WorkoutExerciseEntry(exerciseID: "row", index: 1, sets: [
                    SetEntry(index: 1, weightKg: 0, reps: 0, completed: true,
                             measurement: .init(kind: .distance, seconds: 1230.5, meters: 5000)),
                ]),
                WorkoutExerciseEntry(exerciseID: "pullup", index: 2, sets: [
                    SetEntry(index: 1, weightKg: 20, reps: 8, completed: true,
                             measurement: .init(kind: .assisted, load: .recorded)),
                ]),
            ]
        )

        let fields = rows(csv([session])).map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }

        XCTAssertEqual(fields.map { Array($0[4...10]) }, [
            ["0", "0", "", "timed", "recorded", "60", ""],
            ["0", "0", "", "distance", "recorded", "1230.5", "5000"],
            ["8", "20", "", "assisted", "recorded", "", ""],
        ])
    }

    func test_mixedHistory_listsNewestFirstAndSkipsActiveWorkout() throws {
        let older = try date(day: 1, hour: 9)
        let newer = try date(day: 2, hour: 9)
        let set = SetEntry(index: 1, weightKg: 20, reps: 5, completed: true)
        let sessions = [
            WorkoutSession(name: "Older", startedAt: older, finishedAt: older.addingTimeInterval(600),
                           exercises: [WorkoutExerciseEntry(exerciseID: "bench", index: 0, sets: [set])]),
            WorkoutSession(name: "Newer", startedAt: newer, finishedAt: newer.addingTimeInterval(600),
                           exercises: [WorkoutExerciseEntry(exerciseID: "bench", index: 0, sets: [set])]),
            WorkoutSession(name: "In progress", startedAt: newer.addingTimeInterval(3600),
                           exercises: [WorkoutExerciseEntry(exerciseID: "bench", index: 0, sets: [set])]),
        ]

        let names = rows(csv(sessions)).map { $0.split(separator: ",")[1] }

        XCTAssertEqual(names, ["Newer", "Older"])
    }

    func test_namesAndNotesWithCommasQuotesNewlinesAndFormulas_areEscaped() throws {
        let start = try date(day: 14, hour: 12)
        let session = WorkoutSession(
            name: "Legs, \"heavy\"",
            startedAt: start,
            finishedAt: start.addingTimeInterval(60 * 60),
            exercises: [
                WorkoutExerciseEntry(exerciseID: "squat", index: 0, sets: [
                    SetEntry(index: 1, weightKg: 120, reps: 3, note: "=HYPERLINK(\"x\")", completed: true),
                ]),
            ],
            note: "Line one\nLine two"
        )

        let output = csv([session])

        XCTAssertTrue(output.contains(",\"Legs, \"\"heavy\"\"\",Squat,"), output)
        XCTAssertTrue(output.contains(",\"'=HYPERLINK(\"\"x\"\")\","), output)
        XCTAssertTrue(output.hasSuffix(",\"Line one\nLine two\"\n"), output)
    }
}
