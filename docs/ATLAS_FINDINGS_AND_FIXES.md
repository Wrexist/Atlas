# Atlas — findings och lösningar

Skriven 2026-08-04, uppdaterad 2026-08-05. Överlämning från sessionen som
fick CI att fungera igen, fixade PR #154 och #155, och gick igenom appen
på TestFlight.

**PR #155 är mergad och grön.** Byggen och lintsteg passerade.

**Läs först:** testlistan i "Kvarvarande arbete" punkt 1 var fel. Den
byggde på en tidigare körning. Den faktiska listan — hämtad ur
jobbloggen för run `30971354484` — står nu där, och den är **32 tester,
inte 17**. Skillnaden är nästan helt `StoreServiceTests`, femton stycken
som föll på samma saknade fil och som ingen räknade.

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

**Klart.** `pinnedFooter(_:)` finns i designsystemet — `safeAreaInset` +
ogenomskinlig botten + fade som *avslutas ovanför* knappen — och
`rule_floating_footer` gatar mönstret.

Två saker föll ut av det. Onboarding hade bara halva fixen: dess gradient
öppnade på opacity 0 och blev opak först runt mitten av knappen, alltså
samma genomlysning som paywallen hade. Och regeln hittade en tredje
förekomst direkt — datumchippet över fotobläddraren. Den är den
*legitima* användningen av formen, så regeln är avgränsad till footers
som håller en kontroll: en bildtext kan inte göra något oåtkomligt, och
en regel som skriker på den blir ignorerad.

### A2. Ett steg som inte kan misslyckas får inte rapportera grönt
`test-compile` slutade på `|| true` och var grönt i månader medan
testmålet inte kompilerade. `Unit Tests` var en attrapp som körde
`touch test-output.log` och laddade upp 211 byte.

**Kvar:** ta bort `continue-on-error` från `Unit Tests` när sviten är grön.
Tolv tester kvar (se punkt 1). Ta bort flaggan i samma commit som det
sista av dem — annars är det enda som håller sviten grön att ingen tittar.

### A3. Repo-data som sanning för testfixturer
`exerciseID: "Barbell_Bench_Press"` finns inte — datasetet kallar den
`Barbell_Bench_Press_-_Medium_Grip`. Uppslaget gav tomt, sex tester föll.
**Värst:** testerna som asserterar tomhet passerade perfekt på två tomma
dictionaries. Trasig fixtur fick negativa tester att passera av fel skäl.

**Klart.** `check-copy-claims.py` verifierar varje `exerciseID:` mot
`exercises.json`, avgränsat till testfiler som faktiskt slår mot
`ExerciseLibrary` — på övriga ställen är id:t en ogenomskinlig nyckel och
`"Squat"` duger för en 1RM-uträkning som aldrig konsulterar datasetet.
Allowlistan för avsiktliga negativfall kontrolleras åt båda hållen. Körs
utan Xcode.

### A4. Generiska destinationer för allt som bara kompilerar
`name:iPhone 16` finns inte på alla runner-images. Samma workflow, två
runners, en hittade den och en inte — den gatande jobbet var ett myntkast.
**Gjort:** `generic/platform=iOS Simulator` för `build` och
`build-for-testing`; namngiven enhet resolvas i runtime via `simctl` endast
där tester körs.

---

## Kvarvarande arbete, i ordning

### 1. De återstående testfelen — 12 kvar av 32

Hämta alltid listan ur loggen, inte ur ett dokument. Så här:

```
gh run view <run-id> --log --job <build-check-id> | grep 'PeptideTests/.*error:'
```

**Åtgärdade den 5 aug (20 tester):**

| Kluster | Antal | Rotorsak |
|---|---|---|
| `StoreServiceTests` | 15 | `Products.storekit` fanns i varken app- eller testbundle. `SKTestSession(configurationFileNamed:)` läser ur *testbundlen*; app-targetet exkluderar filen med flit. Nu kopierad till testtargetet. |
| `ShareCardRenderer` | 2 | Förväntade 1080×1350. Renderaren har alltid varit 1080×1920 — förväntan stämde aldrig. Asserterar mot `canvasSize` nu. |
| `PerformanceAgeEngine` clamp | 2 | Testade en clamp som **inte går att nå**: drivarna summerar till max +6.3 / −4.3 mot ett tak på ±8. Taket är ett skyddsnät, inte ett mål. |
| `MuscleGroupAndEquipment` | 1 | `abductors` → `.glutes` sedan audit Train M5; testet låg kvar på `.legs`. |
| `PeptideProtocolAuthorship` | 1 | ISO8601 skriver hela sekunder; testet krävde millisekundprecision. |

Två av de här var värda mer än sin fix. `PerformanceAgeEngine`-paret
asserterade beteende motoren aldrig kunnat producera — och testet
*direkt ovanför* dem asserterade redan att summan landar oklampad.
Sviten motsade sig själv och ingen läste den. `ShareCardRenderer` hade
tredje testet i samma fil rätt (mot `canvasSize`) medan två höll en egen
kopia av siffran.

**Kvar (12), grupperade på felets form — inte per fil:**

*Ser ut som riktiga defekter (appen, inte förväntan):*
- `WorkoutSessionService.test_startWorkout_discardsPriorActive` — samma
  UUID före och efter. Den föregående aktiva passet kastas inte.
- `AchievementService` — `latestUnlock` är inte nil vid andra anropet.
- `NutritionLabelOCR` ×2 — parsern ger `1.0` där etiketten säger `240`
  respektive `30`. Den plockar troligen portionsantalet.
- `LifestyleDataStore` — 4 istället för 2; dagsisoleringen läcker.
- `BarcodeScanHistory` — decay ger 0.736 mot förväntat 1.0.

*Ser ut som ruttnad förväntan:*
- `BiomarkerSeries.formatValue` — 72.0 mot 72.1.
- `GoalCountdownCard` — 0 mot 1 vecka.
- `AIResearchService` — `.serviceUnavailable` istället för
  `.requestFailed`; felmappningen är förmodligen medvetet finare nu.
- `SmartCyclePlanner` — naken `XCTAssertTrue`, ingen text. Ge den ett
  meddelande först, annars går det inte att avgöra.

*Datafel, inte kodfel:*
- `ExerciseLibrary.test_load_everyExercise_hasInstructions` — fem poster
  i `exercises.json` saknar instruktioner (`Iron_Cross`,
  `One-Arm_Kettlebell_Swings`, `Push_Press`, m.fl.). Antingen fyll dem
  eller allowlista dem uttryckligen — datasetet är uppströms.

Ställ alltid frågan: **regresserade appen, eller ruttnade förväntan?** De
kräver motsatta fixar, och fem av de tjugo som är lösta var det senare.

### 2. `?? 0` i accuracy-assertions — **klart**
`XCTAssertEqual(x?.y ?? 0, 0.0, accuracy: 0.01)` passerar tyst när
parsningen ger nil — den jämför noll mot noll. Tre av dem asserterade
mot ett förväntat värde på just noll, alltså passerade de i tysthet
redan. Alla 30 förekomster i 11 filer går genom `XCTUnwrap` nu.

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

### 4. Paywallens komposition — **klart**
Rubriken var hårdkodad till månadspitchen — "3 Days Free", "Atlas Pro
Monthly", "Then $9.99/month" — medan `.annual` är det som laddas valt och
det som CTA:n rakt under säger att den startar. Enda priset ovanför fold
gällde alltså en plan knappen inte skulle köpa, och det riktiga beloppet
låg i tier-kortet under fold. Rubriken följer valt tier nu.

Nedräkningen bar en deadline med samma visuella tyngd som ett filterchip.
Den är ett kort nu, med klockan i display-storlek på egen rad och fönstret
som tömmer sig under — stapeln är det som får den att läsas som tid som
rinner ut istället för en siffra som råkar ändra sig.

### 5. Död yta på App Store-skärmarna — **klart**
932px respektive 822px under sista elementet. Nu 224px och 162px, i linje
med de övriga sex.

Paywallen öppnar på nedräkningen appen faktiskt visar, och funktionslistan
är appens egna fem rader — utfall istället för delsystem. Den namngav
maskineri ("full Biology tab", "Weekly Summary"), vilket säger vad man
köper men inte vad som blir bättre, och den beskrev ett paywall användaren
inte landar på. Protokollskärmen fick de två sakerna den handlade om men
aldrig visade: cykeln den är 14 dagar in i, och vad Atlas gör med
följsamhetssiffran den leder med.

**Kvar:** `02-score`, `03-train` och `04-meals` har 480–550px under sista
elementet — mindre än de två ovan, men de saknar också tabbar. Värt en
titt, inte samma akuta storlek.

Rendera med `node render.mjs` (`--ipad` för iPad-varianterna), verifiera
med `node measure.mjs phone`. Obs: `02-score` och `06-habits` renderar
inte deterministiskt — de ger en ny PNG varje körning utan att HTML:en
ändrats. Committa dem inte i onödan.

### 6. Verifiera på riktig enhet
- `03f7853` byggde om layout-containern för **alla 18 onboarding-steg**
- `NSPhotoLibraryUsageDescription` (i #154) förhindrar en hård
  TCC-terminering i foto-scannern
- `pinnedFooter` rör nu **både** onboarding-footern och paywallens — samma
  modifier, två skärmar. Onboardingens bakgrund ändrades från en gradient
  över hela footerhöjden till opak botten + 16px fade, och den slutade
  sätta `allowsHitTesting(false)`. Titta på ett scrollande steg (mål,
  kroppsmått) och kontrollera att sista raden går fri från knappen.
- Paywallens rubrik byter innehåll när man växlar tier. Kontrollera att
  övergången inte hoppar i höjd — `annualPrice` och `"3 Days Free"` är
  olika långa strängar i samma 44pt-rad.

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
