import SwiftUI

struct ReadyHero: View {
    let bounceTrigger: Int
    var isActive: Bool = true

    var body: some View {
        MilestoneArtwork(size: 144, trigger: bounceTrigger, isActive: isActive)
    }
}
