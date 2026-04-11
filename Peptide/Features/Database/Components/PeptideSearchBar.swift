import SwiftUI

struct PeptideSearchBar: View {
    @Binding var text: String

    var body: some View {
        GlassTextField(placeholder: "Search peptides, benefits...", text: $text)
    }
}
