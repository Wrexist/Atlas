import SwiftUI
import UIKit

/// Step-by-step in-app guide in Swedish. Surfaced automatically the first time
/// the main app appears after onboarding, and from the Profile screen any time.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    @State private var currentStep = 0
    @State private var bounceTrigger = 0

    private let steps: [TutorialStep] = TutorialStep.allSteps

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $currentStep) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        TutorialStepView(step: step, index: index, total: steps.count, bounceTrigger: bounceTrigger)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springSmooth, value: currentStep)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: currentStep) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bounceTrigger &+= 1
        }
        .onAppear { hasSeenTutorial = true }
    }

    private var header: some View {
        HStack {
            Text("Guide")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            Text("\(currentStep + 1) / \(steps.count)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(AppColor.surfaceSecondary.opacity(0.6))
                            .overlay {
                                Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                            }
                    }
                    .liquidGlass(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stäng guide")
            .padding(.leading, Spacing.sm)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.sm)
    }

    private var footer: some View {
        VStack(spacing: Spacing.md) {
            stepDots

            HStack(spacing: Spacing.md) {
                if currentStep > 0 {
                    GlassButton(title: "Tillbaka", style: .secondary, isFullWidth: true) {
                        withAnimation(AppAnimation.springSmooth) {
                            currentStep = max(0, currentStep - 1)
                        }
                    }
                }

                GlassButton(
                    title: isLastStep ? "Klar" : "Nästa",
                    icon: isLastStep ? "checkmark" : "arrow.right",
                    style: .primary,
                    isFullWidth: true
                ) {
                    if isLastStep {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } else {
                        withAnimation(AppAnimation.springSmooth) {
                            currentStep = min(steps.count - 1, currentStep + 1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, Spacing.lg)
    }

    private var stepDots: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? AppColor.accentLight : AppColor.glassBorder)
                    .frame(width: index == currentStep ? 22 : 6, height: 6)
                    .animation(AppAnimation.springSnappy, value: currentStep)
            }
        }
    }

    private var isLastStep: Bool { currentStep == steps.count - 1 }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                AppColor.accentPrimary.opacity(0.18),
                AppColor.background,
                AppColor.background,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Step Model

struct TutorialStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let summary: String
    let bullets: [String]
    let tip: String?

    static let allSteps: [TutorialStep] = [
        .init(
            icon: "hand.wave.fill",
            title: "Välkommen till PeptideX",
            summary: "Den här guiden visar dig steg för steg hur du kommer igång och får ut det mesta av appen.",
            bullets: [
                "Spåra dina peptidprotokoll med precision",
                "Få smarta påminnelser och insikter",
                "All data stannar privat på din enhet"
            ],
            tip: "Du kan öppna den här guiden igen när som helst från fliken Profil."
        ),
        .init(
            icon: "list.clipboard.fill",
            title: "Steg 1 — Skapa ditt protokoll",
            summary: "Gå till fliken Protokoll och tryck på plus-knappen för att skapa ett nytt protokoll.",
            bullets: [
                "Tryck på Protokoll längst ner",
                "Tryck på + uppe till höger",
                "Ge protokollet ett namn, t.ex. \"Återhämtning\""
            ],
            tip: "Kostnadsfri plan tillåter upp till 3 aktiva protokoll. Pro ger obegränsat antal."
        ),
        .init(
            icon: "flask.fill",
            title: "Steg 2 — Lägg till peptider",
            summary: "Välj peptider från databasen och ange dos, frekvens och tid.",
            bullets: [
                "Tryck på Lägg till peptid",
                "Sök i databasen med över 50 peptider",
                "Ställ in dos (mg/IU), frekvens och tid på dygnet"
            ],
            tip: "PeptideX varnar dig automatiskt om två peptider inte bör kombineras."
        ),
        .init(
            icon: "bell.badge.fill",
            title: "Steg 3 — Aktivera påminnelser",
            summary: "Aktivera notiser så att du aldrig missar en dos. Du kan justera tysta timmar.",
            bullets: [
                "Tillåt aviseringar när du blir tillfrågad",
                "Påminnelser skickas vid varje schemalagd dos",
                "Tysta timmar respekteras automatiskt"
            ],
            tip: "Glömde du tillåta aviseringar? Inställningar → PeptideX → Aviseringar."
        ),
        .init(
            icon: "checkmark.circle.fill",
            title: "Steg 4 — Logga din dos",
            summary: "När du tagit en dos, öppna Hem-fliken och tryck på doskortet för att logga den.",
            bullets: [
                "Tryck på Hem för dagens schema",
                "Tryck på en dos och välj Logga",
                "Lägg till anteckningar eller injektionsplats om du vill"
            ],
            tip: "Du kan också logga en dos direkt från låsskärmen via en widget."
        ),
        .init(
            icon: "chart.xyaxis.line",
            title: "Steg 5 — Följ dina framsteg",
            summary: "Fliken Analys visar streaks, följsamhet och trender över tid.",
            bullets: [
                "Se din följsamhet per vecka och månad",
                "Filtrera per peptid eller protokoll",
                "Få automatiska insikter när mönster upptäcks"
            ],
            tip: "Pro låser upp alla tidsintervall och avancerade insikter."
        ),
        .init(
            icon: "heart.text.square.fill",
            title: "Steg 6 — Anslut Apple Health",
            summary: "Koppla Apple Health för att korrelera dina protokoll med HRV, sömn och aktivitet.",
            bullets: [
                "Profil → Apple Health → Anslut",
                "PeptideX skriver aldrig till din hälsodata",
                "Se hur dina peptider påverkar din återhämtning"
            ],
            tip: "Du kan koppla från när som helst i Inställningar."
        ),
        .init(
            icon: "icloud.fill",
            title: "Steg 7 — Säkerhetskopiera",
            summary: "Logga in med Apple-ID för att synka och säkerhetskopiera dina protokoll mellan enheter.",
            bullets: [
                "Profil → Konto → Logga in med Apple",
                "Synkar automatiskt över iCloud",
                "Exportera CSV eller JSON för egen backup"
            ],
            tip: "All synkning är krypterad och du kan logga ut när du vill."
        ),
        .init(
            icon: "star.circle.fill",
            title: "Steg 8 — Lås upp Pro",
            summary: "PeptideX Pro ger obegränsade protokoll, AI-insikter, alla widgets och mer.",
            bullets: [
                "Obegränsade protokoll och peptider",
                "Full analys med export",
                "Premium-widgets och Apple Watch"
            ],
            tip: "Nya användare får ett 3-dagars gratis Liquid Glass-erbjudande i onboardingen."
        ),
        .init(
            icon: "sparkles",
            title: "Klart — kör igång!",
            summary: "Du är redo att börja spåra dina protokoll. Lycka till med dina mål!",
            bullets: [
                "Skapa ditt första protokoll i dag",
                "Logga din första dos och starta din streak",
                "Återbesök den här guiden när som helst"
            ],
            tip: "Tryck på Klar nedan för att börja använda PeptideX."
        ),
    ]
}

// MARK: - Step View

private struct TutorialStepView: View {
    let step: TutorialStep
    let index: Int
    let total: Int
    let bounceTrigger: Int

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.xl) {
                Spacer(minLength: Spacing.lg)

                HeroIcon(symbol: step.icon, size: 96, bounceTrigger: bounceTrigger)
                    .padding(.bottom, Spacing.sm)

                VStack(spacing: Spacing.md) {
                    Text(step.title)
                        .font(AppFont.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.textPrimary, AppColor.accentLight],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text(step.summary)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.md)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(step.bullets.enumerated()), id: \.offset) { idx, bullet in
                            stepBullet(number: idx + 1, text: bullet)
                        }
                    }
                }

                if let tip = step.tip {
                    GlassCard(tinted: true) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColor.accentLight)
                                .padding(.top, 2)

                            Text(tip)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                    }
                }

                Spacer(minLength: Spacing.lg)
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func stepBullet(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text("\(number)")
                .font(AppFont.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }

            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    TutorialView()
        .preferredColorScheme(.dark)
}
