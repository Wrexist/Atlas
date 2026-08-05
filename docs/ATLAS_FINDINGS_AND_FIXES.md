# Atlas — findings och lösningar

Skriven 2026-08-04. Överlämning från sessionen som fick CI att fungera
igen, fixade PR #154 och #155, och gick igenom appen på TestFlight.

**Läs först:** kontrollera att [PR #155](https://github.com/Wrexist/Peptide-ai/pull/155)
är grön. Sju commits ligger där och **ingen av dem var kompilerad när de
skrevs** — `c122915` introducerar `AppColor` i `MuscleMapView` för första
gången, och just den sortens typ-/API-krock har brutit bygget fyra gånger.

---

## Miljöns spelregler

- `pr-checks.yml` är `on: pull_request`. En push till en gren **utan öppen
  PR kör ingenting** — den producerar ett namnlöst `startup_failure` och
  verifierar noll. Arbeta alltid under en öppen PR.
- Ingen Swift-toolchain i containern. `scripts/check.sh` täcker design-lint,
  kontrast, copy-claims och Node-proxytesterna. **CI är enda sanningen för
  allt Swift.**
- **Läs loggar, aldrig jobbslutsatser.** `Unit Tests` är fortfarande
  `continue-on-error`, så dess gröna betyder "kördes", inte "passerade".
- Felinformation finns i artefakten `test-results-*`, eller genom att greppa
  jobbloggen efter `XCTAssert.*failed` — den bär faktiskt-vs-förväntat.

---

## Det är inte 35 problem, det är sex rotorsaker

### A1. Ett mönster för fastnitade CTA:er över scrollande innehåll
*Löste: Gender oåtkomlig, paywall-överlappet.*

Footern var `VStack { Spacer(); footer }` i en ZStack — en flytande overlay
som reserverar **noll** utrymme. Gender-fältet var inte avklippt, det var
oåtkomligt. Paywallens bakgrund började dessutom på `.opacity(0)`, alltså
helt genomskinlig exakt där knappen sitter.

**Kvar att göra:** lyft mönstret till en `pinnedFooter(_:)`-modifier i
designsystemet — `safeAreaInset` + ogenomskinlig botten + fade som
*avslutas ovanför* knappen — och en lint-regel mot `VStack { Spacer(); X }`
i en ZStack över en ScrollView. Symptomen är fixade; mönstret kan återkomma.

### A2. Ett steg som inte kan misslyckas får inte rapportera grönt
`test-compile` slutade på `|| true` och var grönt i månader medan
testmålet inte kompilerade. `Unit Tests` var en attrapp som körde
`touch test-output.log` och laddade upp 211 byte.

**Kvar:** ta bort `continue-on-error` från `Unit Tests` när sviten är grön.

### A3. Repo-data som sanning för testfixturer
`exerciseID: "Barbell_Bench_Press"` finns inte — datasetet kallar den
`Barbell_Bench_Press_-_Medium_Grip`. Uppslaget gav tomt, sex tester föll.
**Värst:** testerna som asserterar tomhet passerade perfekt på två tomma
dictionaries. Trasig fixtur fick negativa tester att passera av fel skäl.

**Kvar:** lägg i `check-copy-claims.py` att varje `exerciseID:` i
`PeptideTests/` måste finnas i `exercises.json`, med allowlist för
avsiktliga negativfall (`definitely_not_real`). Körs utan Xcode.

### A4. Generiska destinationer för allt som bara kompilerar
`name:iPhone 16` finns inte på alla runner-images. Samma workflow, två
runners, en hittade den och en inte — den gatande jobbet var ett myntkast.
**Gjort:** `generic/platform=iOS Simulator` för `build` och
`build-for-testing`; namngiven enhet resolvas i runtime via `simctl` endast
där tester körs.

---

## Kvarvarande arbete, i ordning

### 1. De 17 återstående testfelen
11 av 28 fixade. Kvar: `ShareCardRenderer` ×2, `PerformanceAgeEngine`
clamp ×2, `NutritionLabelOCR` ×2, plus enstaka i `AIResearchService`,
`AchievementService`, `BarcodeScanHistory`, `BiomarkerSeries`,
`ExerciseLibrary`, `GoalCountdownCard`, `LifestyleDataStore`,
`MuscleGroupAndEquipment`, `PeptideProtocolAuthorship`,
`SmartCyclePlanner`, `WorkoutSessionService`.

**Smart approach:** gruppera på felmeddelandets *form*, inte per fil. De
två kluster som är lösta var vardera **en** rotorsak som täckte 5 och 6
tester. Ställ alltid frågan: regresserade appen, eller ruttnade förväntan?
De kräver motsatta fixar.

### 2. `?? 0` i accuracy-assertions (~9 st)
`XCTAssertEqual(x?.y ?? 0, 251, accuracy: 1)` passerar tyst när parsningen
ger nil — den jämför mot noll. Byt till `XCTUnwrap`. Finns i
`NutritionLabelOCRTests`, `WeeklySummaryEngineTests`,
`TodayOverviewSnapshotTests`, `MuscleGainsEngineTests`.

### 3. Muskelkartan — assets
Paletten är fixad i `c122915` (neutral baslinje, accent-drivna toner).
Vilotillståndet var **köttrött**, så hela kroppen var målad innan du
tränat något — färgen, det enda vyn har att kommunicera med, var förbrukad.
Fitbod, Hevy och Strong löser det identiskt: grått = otränat, färg = data.

**Kvar, i denna ordning:**
1. **Beskär vid halsen.** Störst effekt per krona — de uttryckslösa ovala
   huvudena är uncanny och tillför noll. Fitbod beskär, Hevy siluett.
2. **Platta vektorfyllningar** utan diagonal skraffering. Skrafferingen är
   det som läser som medicinsk lärobok.
3. **Lägg till en legend.** Värmeramp utan nyckel är dekoration, inte data.

### 4. Paywallens komposition
Överlappet och säljtexten är fixade (`b9ffd86`, `b1c2043`). Kvar: ge
nedräkningen verklig tyngd (den är en tunn pill som inte bär en deadline),
och **flytta priset ovanför fold** — tier-väljaren ligger under, så beloppet
är osynligt i viloläge. Ett paywall där man måste scrolla för att se priset
konverterar sämre.

### 5. Död yta på App Store-skärmarna
760–880px under sista elementet på `07-protocols.html` och `08-paywall.html`.
Fyll med innehåll som säljer, inte luft. Rendera med `node render.mjs`,
verifiera med `node measure.mjs phone` (mäter numera geometri, inte bara färg).

### 6. Verifiera på riktig enhet
- `03f7853` byggde om layout-containern för **alla 18 onboarding-steg**
- `NSPhotoLibraryUsageDescription` (i #154) förhindrar en hård
  TCC-terminering i foto-scannern

---

## Verktygen — så de slutar ljuga

- **`rule_glow` rapporterade noll medan nio accent-glow fanns.** Den rena
  rapporten skrevs in i auditen som bevis. `scripts/test_design_lint.py`
  finns nu med 38 självtester. **Regel: ingen ny lint-regel utan både ett
  positivt och ett negativt testfall.** En blind kontroll är sämre än ingen,
  för den blir trodd.
- **`check.sh` tolererade tre fel** eftersom kontrastmätaren inte kunde se
  SVG-gradienter och rapporterade en guldmedalj som 1.04:1. Tröskeln var
  satt att svälja exakt tre — den hade svalt de tre nästa *äkta* också.
  Nu 0, och mätaren hit-testar det som faktiskt målas.
- **`DOMAIN_PALETTE_FILES`-undantaget** släppte igenom köttfärgerna
  oexaminerade. Sätt datum på varje post och läs om dem. En nödutgång som
  aldrig omprövas är en blind fläck med dokumentation.
- **Fyll på Codex-krediter.** Den hittade tre äkta defekter på #154 som
  ingen kompilator kan se — delad budget som debiterades för avvisade
  requests, kostnad från en spoofbar `content-length`, och workout-skrivningar
  som lämnade Today-tidslinjen inaktuell. Den gick tom på #155.

---

## Medvetet **inte** rekommenderat

- **Maskinöversätt inte lokaliseringen** (13 %, 306 meningar). Det är
  doserings- och säkerhetstext. Beställ riktiga översättningar eller
  begränsa språkväljaren till det som faktiskt är täckt.
- **72 döda katalognycklar** — kosmetiskt, kostar inget att låta ligga.
- **Bygg inte en egen statisk Swift-typkontroll.** Två försök i den här
  sessionen, båda trasiga; det andra hade rapporterat 343 påhittade
  defekter. Att bygga en halv typechecker för att slippa vänta sex minuter
  är fel affär.
- **De sju övriga okända `exerciseID`** — avsiktliga, eller i tester som
  aldrig slår mot biblioteket.

---

## Den slutsats som betyder mest

Appen hade 20 lint-regler, 244 kontrastpar, 48 proxytester och en grön
bräda — och kunde ändå inte kompilera sitt testmål, kraschade i
foto-scannern, hade ett oåtkomligt formulärfält och en paywall som skrev
ovanpå sig själv.

**Varje defekt som faktiskt betydde något kom från en skärmdump.** Inte en
enda syntes för verktygen.

Det är inte ett argument mot verktygen — det är ett argument mot att lita på
dem som bevis för något de aldrig mätte. Den bästa investeringen i
appkvalitet härifrån är inte fler regler, utan att appen körs på en telefon
regelbundet. `Screenshots`-workflowet finns redan och har aldrig körts
skarpt. Få igång det så kommer den signalen automatiskt.
