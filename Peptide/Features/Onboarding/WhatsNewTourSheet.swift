import SwiftUI
import UIKit

/// Paginated "What's New" tour. Surfaces the major features
/// shipped in v2.0 to existing users who installed before this
/// update — fresh installs get the regular onboarding flow
/// instead, so this prompt is invisible to them.
///
/// Design intent: feel like Apple's "What's New in <App>" splash
/// screens. Big hero glyph in a tinted glass card, generous
/// type hierarchy, page-indicator dots, single primary CTA on
/// the last page, soft cross-fade between pages. Haptic feedback
/// on every page swipe. Reduces motion gracefully when the user
/// has Reduce Motion turned on.
///
/// Self-contained — the host (`PeptideApp`) only has to present
/// it; the sheet handles its own pagination, completion stamp,
/// and dismissal.
struct WhatsNewTourSheet: View {
    let pages: [WhatsNewPage]
    let onComplete: () -> Void

    @State private var currentIndex: Int = 0

    private var isLastPage: Bool {
        currentIndex >= pages.count - 1
    }

    var body: some View {
        ZStack {
            backgroundLayer
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: Spacing.md)
                pageContent
                    .padding(.horizontal, Spacing.screenPadding)
                Spacer(minLength: Spacing.md)
                bottomControls
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, Spacing.lg)
            }
        }
        // Haptics aren't motion — `Haptics` honours the user's own
        // toggle, so the page tick isn't gated on Reduce Motion.
        .onChange(of: currentIndex) { _, _ in
            Haptics.selection()
            // Move VoiceOver to the new page instead of leaving it parked
            // on the Continue button, as onboarding does.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    // MARK: - Background

    /// One soft accent wash from the top, the same on every page, with a
    /// vignette that keeps the centre content readable on every theme.
    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [AppColor.accentPrimary.opacity(0.18), AppColor.background],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [AppColor.background.opacity(0.0), AppColor.background.opacity(0.55)],
                center: .center,
                startRadius: 220,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                onComplete()
            } label: {
                Text("Skip")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .glassControl(.capsule, interactive: false)
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityLabel("Skip tour")
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Page content

    /// Paged TabView gives us swipe-to-paginate with the system
    /// hit-test region for free. Page index dots are drawn
    /// separately below so we can style them to match the rest
    /// of the design system.
    private var pageContent: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                pageView(page: page)
                    .tag(index)
                    .padding(.horizontal, Spacing.xs)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
    }

    /// Scrolls so a long body plus four bullets stays reachable at large
    /// Dynamic Type sizes instead of clipping under the CTA.
    private func pageView(page: WhatsNewPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroCard(page: page)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(page.eyebrow)
                        .font(AppFont.eyebrow)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(AppColor.textSecondary)
                    Text(page.title)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.body)
                        .font(AppFont.scaled(16))
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                bulletList(page: page)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }

    /// Tinted glass card holding the hero glyph in the accent. The glyph
    /// bounces once on page change so the eye catches it as new content;
    /// `symbolEffect` sits it out under Reduce Motion on its own.
    private func heroCard(page: WhatsNewPage) -> some View {
        Image(systemName: page.icon)
            .font(AppFont.scaled(60, weight: .semibold, relativeTo: .title1))
            .foregroundStyle(AppColor.accentPrimary)
            .symbolEffect(.bounce, value: currentIndex)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .glassSurface(cornerRadius: Spacing.sheetCornerRadius, tinted: true)
    }

    private func bulletList(page: WhatsNewPage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                bulletRow(bullet)
            }
        }
    }

    private func bulletRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.22))
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .accessibilityHidden(true)
            Text(text)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Spacing.md) {
            pageIndicator
            primaryButton
        }
    }

    /// Dots indicator drawn manually so the active dot takes the
    /// accent and stretches into a capsule, which SwiftUI's built-in
    /// `.page` indicator can't do.
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { index in
                let isActive = index == currentIndex
                Capsule()
                    .fill(isActive ? AppColor.accentPrimary : AppColor.textTertiary.opacity(0.4))
                    .frame(width: isActive ? 22 : 6, height: 6)
                    .appAnimation(AppAnimation.springSnappy, value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(pages.count)")
    }

    /// Primary CTA. Reads "Continue" until the last page, then
    /// becomes "Get started" — psychologically that final button
    /// feels like a commitment rather than another page-turn.
    /// The app's one primary CTA, filled with the contrast-checked CTA
    /// stops.
    private var primaryButton: some View {
        PrimaryCTAButton(title: isLastPage ? "Get started" : "Continue") {
            advance()
        }
        .accessibilityLabel(isLastPage ? "Get started" : "Continue to next page")
    }

    // MARK: - Behaviour

    private func advance() {
        if isLastPage {
            Haptics.success()
            onComplete()
            return
        }
        AppAnimation.with(AppAnimation.springSmooth) {
            currentIndex += 1
        }
    }
}
