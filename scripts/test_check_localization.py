"""Regression checks for check-localization.py's LocalizedStringKey argument scan."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("loc", Path(__file__).with_name("check-localization.py"))
loc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loc)

HEADER = """
struct SectionHeader: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    var body: some View { Text(title) }
}
"""


def scan(source: str) -> set[str]:
    return scan_files({"View.swift": source})


def scan_files(files: dict[str, str]) -> set[str]:
    real_repo = loc.REPO
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "App").mkdir()
        for name, source in files.items():
            (Path(tmp) / "App" / name).write_text(source)
        loc.REPO = Path(tmp)
        try:
            return set(loc.localized_key_arguments(("App",)))
        finally:
            loc.REPO = real_repo


class LocalizedKeyArgumentTests(unittest.TestCase):
    def test_memberwise_view_parameters_are_found(self):
        found = scan(HEADER + 'let v = SectionHeader(eyebrow: "Today", title: "Daily checklist")')
        self.assertEqual(found, {"Today", "Daily checklist"})

    def test_string_parameter_is_not_a_catalog_lookup(self):
        found = scan('struct Row: View {\n    let title: String\n}\nlet r = Row(title: "Raw name")')
        self.assertEqual(found, set())

    def test_explicit_init_replaces_the_memberwise_one(self):
        source = """
struct Chip: View {
    let title: LocalizedStringKey
    init(title: String) { self.title = LocalizedStringKey(title) }
}
let c = Chip(title: "Not a key")
"""
        self.assertEqual(scan(source), set())

    def test_string_overload_of_the_same_label_wins_and_is_skipped(self):
        source = """
struct Pill: View {
    init(label: LocalizedStringKey) {}
    init(label: String) {}
}
let p = Pill(label: "Ambiguous")
"""
        self.assertEqual(scan(source), set())

    def test_unlabelled_helper_parameter_is_found(self):
        source = """
private func sectionEyebrow(_ text: LocalizedStringKey) -> some View { Text(text) }
let e = sectionEyebrow("Your plan")
"""
        self.assertEqual(scan(source), {"Your plan"})

    def test_same_named_helper_in_another_file_does_not_hide_a_key(self):
        found = scan_files({
            "Detail.swift": 'private func sectionHeader(_ t: LocalizedStringKey) -> some View { Text(t) }\n'
                            'let a = sectionHeader("TODAY\'S DOSES")',
            "History.swift": 'private func sectionHeader(_ t: String, detail: String) -> some View { Text(t) }\n'
                             'let b = sectionHeader("Raw", detail: "x")',
        })
        self.assertEqual(found, {"TODAY'S DOSES"})

    def test_both_branches_of_a_literal_ternary_are_found(self):
        source = """
struct GlassButton: View {
    let title: LocalizedStringKey
}
let b = GlassButton(title: isActive ? "End" : "Start")
"""
        self.assertEqual(scan(source), {"Start", "End"})

    def test_interpolated_literal_is_skipped(self):
        self.assertEqual(scan(HEADER + 'let v = SectionHeader(eyebrow: "Day \\(n)", title: "Plan")'), {"Plan"})

    def test_enum_raw_values_wrapped_for_a_segmented_control_are_found(self):
        source = """
private enum Side: String, CaseIterable {
    case both = "Both", front = "Front"
    case back = "Back"
}
let s = GlassSegmentedControl(
    options: Side.allCases,
    selected: $side,
    label: { LocalizedStringKey($0.rawValue) }
)
"""
        self.assertEqual(scan(source), {"Both", "Front", "Back"})

    def test_comments_and_previews_are_ignored(self):
        source = HEADER + """
// SectionHeader(eyebrow: "Commented", title: "Out")
#Preview {
    SectionHeader(eyebrow: "Preview", title: "Only")
}
"""
        self.assertEqual(scan(source), set())

    def test_ternary_inside_text_and_navigation_title_is_found(self):
        source = """
let t = Text(daysPastEnd > 0 ? "Your cycle has ended" : "Your cycle just finished")
let v = view.navigationTitle(program == nil ? "Create a program" : "Your program")
"""
        self.assertEqual(scan(source), {"Your cycle has ended", "Your cycle just finished",
                                        "Create a program", "Your program"})

    def test_dialog_and_accessibility_modifier_literals_are_found(self):
        source = """
let d = view.confirmationDialog("Discard these results?", isPresented: $shown) {}
let a = view.accessibilityLabel(isOn ? "Included" : "Skipped")
    .accessibilityHint("Toggles whether this result is saved.")
"""
        self.assertEqual(scan(source), {"Discard these results?", "Included", "Skipped",
                                        "Toggles whether this result is saved."})

    def test_literals_returned_as_a_key_are_found(self):
        source = """
private var hint: LocalizedStringKey {
    switch category {
    case .health: return "e.g. 8 (glasses of water)"
    case .custom: "Set whatever number reads naturally."
    }
}
private func spoken(for status: Status) -> LocalizedStringKey {
    switch status {
    case .lower: return "Below your usual range"
    }
}
private var footer: LocalizedStringKey {
    "Not enough recent Health data"
}
"""
        self.assertEqual(scan(source), {"e.g. 8 (glasses of water)", "Set whatever number reads naturally.",
                                        "Below your usual range", "Not enough recent Health data"})

    def test_string_localized_literal_is_found_but_interpolated_one_is_not(self):
        source = 'let a = String(localized: "Your program")\nlet b = String(localized: "Day \\(n)")'
        self.assertEqual(scan(source), {"Your program"})


class UIStringTests(unittest.TestCase):
    def test_confirmation_dialog_title_is_found(self):
        code = '.confirmationDialog("Discard these results?", isPresented: $confirm, titleVisibility: .visible) {}'
        self.assertEqual(loc.ui_strings(code), {"Discard these results?"})

    def test_one_word_picker_label_is_found(self):
        self.assertEqual(loc.ui_strings('Picker("Marker", selection: $marker) {}'), {"Marker"})

    def test_one_word_text_and_interpolated_label_are_skipped(self):
        code = 'Text("Done")\nButton("Log \\(name)") {}\nText("Two words", tableName: "T")'
        self.assertEqual(loc.ui_strings(code), set())

    def test_multi_word_text_is_found(self):
        self.assertEqual(loc.ui_strings('Text("Keep reviewing")'), {"Keep reviewing"})


class UntranslatedArgumentTests(unittest.TestCase):
    STRINGS = {
        "Today": {"localizations": {"sv": {"stringUnit": {"state": "translated", "value": "Idag"}}}},
        "Plan": {},
    }

    def test_missing_key_and_missing_language_are_reported(self):
        gaps = loc.untranslated_arguments({"Today": {"A.swift"}, "Plan": {"B.swift"}, "Goal": {"C.swift"}},
                                          self.STRINGS, {"sv"})
        self.assertEqual(gaps, ["  'Goal' — no catalog key — C.swift", "  'Plan' — no sv — B.swift"])

    def test_real_catalog_covers_every_argument(self):
        catalog = loc.json.loads(loc.CATALOG.read_text())
        shipped = loc.shipped_languages([catalog]) - {"en", "Base"}
        self.assertEqual(loc.untranslated_arguments(loc.localized_key_arguments(), catalog["strings"], shipped), [])


if __name__ == "__main__":
    unittest.main()
