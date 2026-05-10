import Foundation

/// Local lookup for creator referral codes captured on the onboarding
/// attribution step. The spec calls for a Supabase-backed `creator_codes`
/// table with RPC counters for installs / conversions and a web dashboard
/// for monthly payouts — none of that infrastructure exists in this repo
/// yet. For now the seeded codes match the launch list and validation is
/// purely client-side; the install / conversion counters become real when
/// the backend ships.
enum CreatorCodeService {

    /// Seeded codes for the launch list. Mirrors the SQL INSERT in the
    /// product spec so the Supabase migration can be authored 1:1 from
    /// here when the backend lands.
    static let seeded: [CreatorAttribution] = [
        CreatorAttribution(code: "LUCAS50",  creatorName: "Lucas Aoun",        discountPercent: 20),
        CreatorAttribution(code: "NIDDAM",   creatorName: "Nathalie Niddam",   discountPercent: 15),
        CreatorAttribution(code: "BIOHACK",  creatorName: "General Biohacker", discountPercent: 10),
    ]

    /// Case-insensitive, whitespace-trimmed lookup. Returns nil for empty
    /// or unmatched input so the caller can show the inline "Code not
    /// found" error state.
    static func lookup(_ raw: String) -> CreatorAttribution? {
        let needle = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !needle.isEmpty else { return nil }
        return seeded.first { $0.code == needle }
    }
}
