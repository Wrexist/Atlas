# PeptideX — IAP-konfiguration (Steg-för-steg på svenska)

Den här guiden visar hur du sätter upp de tre köpen som appen redan refererar till
i `Peptide/Services/StoreService.swift`:

| Produkt-ID                              | Typ                         | Beskrivning                                              |
| --------------------------------------- | --------------------------- | -------------------------------------------------------- |
| `com.peptidesai.app.pro.monthly`        | Auto-Renewable Subscription | Pro-prenumeration som förnyas varje månad                |
| `com.peptidesai.app.pro.annual`         | Auto-Renewable Subscription | Pro-prenumeration som förnyas varje år (rekommenderad)   |
| `com.peptidesai.app.pro.lifetime`       | Non-Consumable              | Engångsköp som ger Pro för alltid                        |

> Det 3-dagars Liquid Glass-erbjudandet i onboardingen är en **lokal** trial som
> styrs i appen (ingen IAP behövs). Den lagras i `UserDefaults` och kostar 0 kr.

---

## Snabb checklista

Beta av nedan innan du laddar upp en build med IAP-flödet:

- [ ] Apple Developer Program aktivt ($99/år)
- [ ] **Paid Apps Agreement** signerad i App Store Connect
- [ ] Bank- och skatteinformation ifylld (Tax & Banking)
- [ ] Sandbox-testkonto skapat i App Store Connect → Users & Access → Sandbox Testers
- [ ] Tre IAP-produkter skapade (se Steg 3)
- [ ] **Subscription Group** skapad för månads- och årsprenumerationen
- [ ] Lokaliseringar (svenska + engelska) ifyllda för varje produkt
- [ ] Pris satta i alla regioner (eller minst Sverige + USA)
- [ ] Review screenshot uppladdad per prenumeration (1320×2868 eller 2868×1320)
- [ ] StoreKit Configuration-fil skapad i Xcode för lokal testning
- [ ] Sandbox-test genomfört på riktig enhet
- [ ] Restore Purchases testat
- [ ] App Privacy uppdaterad (Purchase History om du loggar köp)

---

## Steg 1 — Aktivera betalda appar

1. Logga in på **App Store Connect** → https://appstoreconnect.apple.com
2. Gå till **Business → Agreements, Tax, and Banking**
3. Signera **Paid Apps Agreement** (kräver behörighet `Account Holder`)
4. Fyll i:
   - **Tax Forms** (för Sverige: W-8BEN för USA-skatt + svensk skattedeklaration)
   - **Banking** (IBAN för utbetalning från Apple)
   - **Contact Info** (Senior Management, Finance, Technical, Legal)

> Utan detta steg syns IAP-produkterna inte i appen — `Product.products(for:)`
> returnerar tom array.

---

## Steg 2 — Skapa en Subscription Group

Prenumerationerna måste tillhöra samma grupp så att användaren kan byta mellan
månad och år.

1. App Store Connect → **My Apps** → **PeptideX**
2. Vänstermeny → **Monetization → Subscriptions**
3. Tryck **+** bredvid *Subscription Groups*
4. **Reference Name:** `PeptideX Pro`
5. Spara

---

## Steg 3 — Skapa de tre IAP-produkterna

### 3a. Månadsprenumeration

1. Gå in i gruppen `PeptideX Pro` → tryck **+** vid *Subscriptions*
2. **Reference Name:** `Pro Monthly`
3. **Product ID:** `com.peptidesai.app.pro.monthly` (måste matcha exakt)
4. **Subscription Duration:** `1 Month`
5. **Price:** välj prisnivå (t.ex. `$9.99` ≈ 99 kr/mån)
6. **Localizations** → lägg till `English (U.S.)` + `Swedish`:
   - **Subscription Display Name (SE):** `PeptideX Pro – Månad`
   - **Description (SE):** `Obegränsade protokoll, AI-insikter, full analys och alla widgets.`
   - **Subscription Display Name (EN):** `PeptideX Pro – Monthly`
   - **Description (EN):** `Unlimited protocols, AI insights, full analytics, and all widgets.`
7. **Review Information:**
   - Screenshot: 1320×2868 (iPhone 6.9″) som visar paywall-skärmen
   - Review notes: `Tap "Profile" tab → "See Plans" → tap Monthly card.`
8. **Save** → status blir `Ready to Submit`

### 3b. Årsprenumeration

Samma som 3a men:
- **Reference Name:** `Pro Annual`
- **Product ID:** `com.peptidesai.app.pro.annual`
- **Subscription Duration:** `1 Year`
- **Price:** ca 40% rabatt mot månad (t.ex. `$59.99/år` om månad är `$9.99`)
- **Display Name (SE):** `PeptideX Pro – År`
- **Display Name (EN):** `PeptideX Pro – Annual`

### 3c. Lifetime (engångsköp)

1. Vänstermeny → **Monetization → In-App Purchases** (inte Subscriptions!)
2. Tryck **+** → **Non-Consumable**
3. **Reference Name:** `Pro Lifetime`
4. **Product ID:** `com.peptidesai.app.pro.lifetime`
5. **Price:** typiskt 3–4× årspris (t.ex. `$199.99`)
6. **Localizations:**
   - **Display Name (SE):** `PeptideX Pro – Livstid`
   - **Description (SE):** `Engångsköp. Lås upp PeptideX Pro för alltid – inga prenumerationer.`
   - **Display Name (EN):** `PeptideX Pro – Lifetime`
   - **Description (EN):** `One-time purchase. Unlock PeptideX Pro forever — no subscription.`
7. **Review Screenshot** + notes
8. Save

---

## Steg 4 — (Valfritt) Introductory Offer & Promo

Om du vill ersätta den lokala 3-dagars trialen med en **riktig** Apple-trial:

1. Öppna prenumerationen `Pro Monthly` (eller Annual) → fliken **Subscription Prices**
2. Tryck **Create Introductory Offer**
3. **Type:** `Free`
4. **Duration:** `3 Days`
5. **Eligibility:** `New Subscribers`
6. Spara

> Då kan du ta bort `startFreeTrial()`-logiken i `StoreService` och lita på
> Apples eligibility-API (`Product.SubscriptionInfo.isEligibleForIntroOffer`).
> Just nu är trialen lokal vilket är enklare men fungerar bara på samma enhet.

---

## Steg 5 — StoreKit Configuration-fil (lokal testning)

Innan sandbox fungerar vill du iterera lokalt utan App Store Connect.

1. Xcode → **File → New → File → StoreKit Configuration File**
2. Spara som `Peptide/Resources/Products.storekit`
3. Lägg till tre produkter med exakt samma ID som ovan:
   - `com.peptidesai.app.pro.monthly` (Auto-Renewable, 1 Month, $9.99)
   - `com.peptidesai.app.pro.annual` (Auto-Renewable, 1 Year, $59.99)
   - `com.peptidesai.app.pro.lifetime` (Non-Consumable, $199.99)
4. För prenumerationerna: skapa en grupp `PeptideX Pro` och lägg båda i den
5. Edit Scheme → **Run → Options → StoreKit Configuration:** välj `Products.storekit`
6. Kör appen i simulator → öppna paywall → produkterna ska dyka upp

> Lägg till `Products.storekit` i `.gitignore` om den innehåller test-priser
> du inte vill committa, eller committa den för reproducerbar teamtestning.

---

## Steg 6 — Sandbox-testning på riktig enhet

1. App Store Connect → **Users and Access → Sandbox Testers** → **+**
2. Skapa ett konto med en **engångsadress** (t.ex. `peptidex+sandbox1@dindomän.se`)
3. På testenheten: **Inställningar → App Store → Sandbox Account → Sign In**
4. Bygg och kör PeptideX från Xcode (inte TestFlight) på enheten
5. Öppna paywall → tryck på en produkt → Apple-dialogen visas med **[Environment: Sandbox]** överst
6. Bekräfta → `StoreService.purchase(...)` ska returnera `true` och `isProUser` blir `true`

### Vanliga sandbox-problem

| Problem                                  | Lösning                                                              |
| ---------------------------------------- | -------------------------------------------------------------------- |
| `products` är tom                        | Paid Apps Agreement ej signerad, eller produkterna är `Missing Metadata` |
| `Cannot connect to iTunes Store`         | Logga ut sandbox-kontot och in igen via Inställningar → App Store    |
| Köp lyckas men `isProUser` stannar false | Kontrollera att produkt-ID matchar konstanterna i `StoreService`     |
| Restore visar inget                      | `AppStore.sync()` kräver att du loggat in i sandbox under aktuell session |

---

## Steg 7 — Restore Purchases

`PaywallView` har redan en **Restore Purchases**-knapp som anropar
`storeService.restorePurchases()`. Apple **kräver** att den finns på alla
betalskärmar. Verifiera att den fungerar i sandbox genom att:

1. Köp `Pro Lifetime` med sandbox-konto A
2. Avinstallera appen
3. Installera om → `isProUser` ska vara `false`
4. Tryck **Restore Purchases** → ska bli `true` igen utan att betala

---

## Steg 8 — Skicka in för granskning

När du laddar upp en build i TestFlight med StoreKit-kod:

1. På första byggets review-omgång måste du **skicka in IAP-produkterna
   tillsammans med appbygget** (inte separat)
2. App Store Connect → din build → **Build Metadata → In-App Purchases and Subscriptions** → välj alla tre produkterna
3. Apple granskar produkterna parallellt med appen (vanligtvis 24–48 h)
4. Status `Ready to Submit` → `Waiting for Review` → `Approved`

> Efter första godkännandet kan framtida pris- och text-ändringar publiceras
> utan ny appgranskning.

---

## Steg 9 — App Privacy & juridiska krav

Eftersom du nu samlar in köpdata måste **App Privacy** uppdateras:

1. App Store Connect → din app → **App Privacy**
2. **+** Data Type → **Purchases → Purchase History** → `Linked to user, App Functionality`
3. Lägg till länk till **Terms of Use (EULA)** i appens metadata
   - Använd Apples standard-EULA eller egen text
4. Lägg till **Privacy Policy URL** (du har redan `docs/privacy.md` på GitHub Pages)

I appen (redan ifixat i `PaywallView`):
- Texten *"Payment will be charged to your Apple ID. Subscription auto-renews
  unless cancelled at least 24 hours before the end of the current period."* — krav

---

## Steg 10 — Verifiera produkt-ID i koden

Öppna och dubbelkolla att konstanterna matchar exakt:

```swift
// Peptide/Services/StoreService.swift
static let monthlyID  = "com.peptidesai.app.pro.monthly"
static let annualID   = "com.peptidesai.app.pro.annual"
static let lifetimeID = "com.peptidesai.app.pro.lifetime"
```

Om du ändrar ID i App Store Connect, uppdatera dessa tre rader.

---

## Felsökning — snabbreferens

```bash
# Visa StoreKit-loggar i Console.app medan appen körs
log stream --predicate 'subsystem == "com.peptidesai.app"' --info

# Återställ sandbox-konto helt
Settings → App Store → Sandbox Account → Sign Out
Settings → Apple ID → Media & Purchases → Sign Out (om du loggat in produktion)

# Tvinga om-inläsning av produkter i appen
StoreService.shared.loadProducts()  // körs automatiskt i PaywallView.task
```

### Loggrader att leta efter

| Logg                                                | Betydelse                              |
| --------------------------------------------------- | -------------------------------------- |
| `Failed to load products: ...`                      | Avtal/metadata problem (Steg 1 + 3)    |
| `Transaction.updates` saknas helt                   | Sandbox-konto ej inloggat              |
| `purchasedProductIDs` har rätt ID men `isProUser=false` | Buggsignal — rapportera                |

---

## Vidare läsning

- Apple — [In-App Purchase Configuration](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/overview-for-configuring-in-app-purchases)
- Apple — [Testing in Sandbox](https://developer.apple.com/apple-pay/sandbox-testing/)
- Apple — [StoreKit 2 Reference](https://developer.apple.com/documentation/storekit)
- WWDC23 — *Meet StoreKit for SwiftUI* (`SubscriptionStoreView`, `ProductView`)

---

När alla rutor i checklistan är ifyllda och sandbox-köpet returnerar
`isProUser = true` på en riktig enhet — då är du redo att skicka build + IAPs
till granskning.
