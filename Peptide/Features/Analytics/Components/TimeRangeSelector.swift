import SwiftUI

struct TimeRangeSelector: View {
    @Binding var selected: TimeRange
    @Namespace private var namespace

    var body: some View {
        GlassSegmentedControl(
            options: TimeRange.allCases,
            selected: $selected,
            namespace: namespace
        )
    }
}
