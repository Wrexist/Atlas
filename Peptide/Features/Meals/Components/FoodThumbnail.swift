import SwiftUI

/// The picture a food gets when it has no product photo: a studio photo
/// of what it is (`Assets.xcassets/Foods`, see tools/food-images), read
/// from its name in English or Swedish, on a tile in a matching colour.
/// Every food in the library, the diary and the scanners then has an
/// image, not a grey box.
struct FoodArtwork: Equatable {
    /// Asset id; the image is `food-<image>`.
    let image: String
    let tint: Color

    static let fallback = FoodArtwork(image: "meal", tint: AppColor.accentPrimary)

    var assetName: String { "food-" + image }

    static func match(_ name: String) -> FoodArtwork {
        let lowered = name.lowercased()
        let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for entry in catalog where entry.keywords.contains(where: { matches($0, words: words, text: lowered) }) {
            return FoodArtwork(image: entry.image, tint: entry.tint)
        }
        return fallback
    }

    /// Short keywords ("te", "ost", "ris") and ones marked with a leading
    /// "=" must be a whole word so they don't fire inside "toast",
    /// "pris" or "vattenmelon"; other longer ones match the start of a
    /// word, which catches plurals and Swedish compounds ("jordgubbsylt",
    /// "kycklingfilé").
    private static func matches(_ keyword: String, words: [String], text: String) -> Bool {
        if keyword.contains(" ") { return text.contains(keyword) }
        if keyword.hasPrefix("=") { return words.contains(String(keyword.dropFirst())) }
        if keyword.count <= 3 { return words.contains(keyword) }
        return words.contains { $0.hasPrefix(keyword) }
    }

    private struct Entry {
        let image: String
        let tint: Color
        let keywords: [String]

        /// `keywords` is "|"-separated, so the catalog stays one flat
        /// literal the compiler can type-check quickly. Split once here;
        /// `catalog` is a static let, so this runs once per entry.
        init(image: String, tint: Color, keywords: String) {
            self.image = image
            self.tint = tint
            self.keywords = keywords.split(separator: "|").map(String.init)
        }
    }

    /// Most specific first: "chocolate milk" is chocolate, "fish burger"
    /// is a burger.
    private static let catalog: [Entry] = [
        Entry(image: "candy", tint: AppColor.destructive,
              keywords: "candy|godis|gummy|gummies|bilar|ferrari|lakrits|licorice|sweets|skumgodis|geléhall|marshmallow"),
        Entry(image: "chocolate", tint: AppColor.macroFat,
              keywords: "chocolate|choklad|cocoa|kakao|marabou|snickers|twix|kitkat"),
        Entry(image: "ice-cream", tint: AppColor.macroWater,
              keywords: "ice cream|gelato|sorbet"),
        Entry(image: "cookie", tint: AppColor.macroCarbs,
              keywords: "cookie|kaka|kakor|kex|biscuit|digestive|brownie"),
        Entry(image: "cake", tint: AppColor.macroCarbs,
              keywords: "cake|tårta|bakelse|muffin|bulle|kanelbulle|cheesecake|donut|munk"),
        Entry(image: "chips", tint: AppColor.warning,
              keywords: "chips|popcorn|crisps|snacks|nachos|ostbågar"),
        Entry(image: "nuts", tint: AppColor.macroFat,
              keywords: "nut|nuts|nöt|nötter|peanut|jordnöt|almond|mandel|cashew|walnut|valnöt"),
        Entry(image: "pizza", tint: AppColor.destructive, keywords: "pizza"),
        Entry(image: "burger", tint: AppColor.macroProtein, keywords: "burger|hamburgare|hamburger"),
        Entry(image: "taco", tint: AppColor.warning, keywords: "taco|tacos|burrito|wrap|quesadilla"),
        Entry(image: "sushi", tint: AppColor.macroWater, keywords: "sushi|maki|nigiri|poke"),
        Entry(image: "noodle-soup", tint: AppColor.macroCarbs, keywords: "ramen|noodle|noodles|nudlar|glassnudlar|pho|soup|soppa"),
        Entry(image: "pasta", tint: AppColor.macroCarbs, keywords: "pasta|spaghetti|penne|lasagne|lasagna|makaroner|fusilli"),
        Entry(image: "rice", tint: AppColor.macroCarbs, keywords: "rice|ris|risotto|basmati|jasminris"),
        Entry(image: "porridge", tint: AppColor.macroCarbs,
              keywords: "oat|oats|havre|havregryn|gröt|porridge|müsli|muesli|granola|cereal|flingor"),
        Entry(image: "bread", tint: AppColor.macroCarbs,
              keywords: "bread|bröd|toast|bagel|knäcke|limpa|fralla|baguette|tortilla|pita"),
        Entry(image: "bacon", tint: AppColor.macroProtein, keywords: "bacon"),
        Entry(image: "sausage", tint: AppColor.macroProtein, keywords: "sausage|korv|hotdog|chorizo|salami"),
        Entry(image: "chicken", tint: AppColor.macroProtein,
              keywords: "chicken|kyckling|karaage|turkey|kalkon|wings"),
        Entry(image: "beef", tint: AppColor.macroProtein,
              keywords: "beef|nötkött|biff|steak|meat|kött|köttfärs|fläsk|pork|mince|lamm|lamb|skinka|ham"),
        Entry(image: "fish", tint: AppColor.macroWater,
              keywords: "fish|fisk|salmon|lax|tuna|tonfisk|torsk|cod|sill|makrill|mackerel"),
        Entry(image: "shrimp", tint: AppColor.warning, keywords: "shrimp|räkor|räka|prawn|prawns|scampi"),
        Entry(image: "egg", tint: AppColor.warning, keywords: "egg|eggs|ägg|omelett|omelette"),
        Entry(image: "cheese", tint: AppColor.warning,
              keywords: "cheese|ost|cheddar|mozzarella|parmesan|brie|feta|halloumi"),
        Entry(image: "butter", tint: AppColor.warning, keywords: "butter|smör|margarine|bregott"),
        Entry(image: "olive-oil", tint: AppColor.success, keywords: "olive|oliv|oil|olja|rapsolja"),
        Entry(image: "milk", tint: AppColor.macroWater,
              keywords: "milk|mjölk|skummjölk|yoghurt|yogurt|kvarg|quark|filmjölk|cottage|skyr|fil|kefir"),
        Entry(image: "tea", tint: AppColor.success, keywords: "tea|te|matcha|chai"),
        Entry(image: "coffee", tint: AppColor.macroFat,
              keywords: "coffee|kaffe|latte|espresso|cappuccino|americano|flat white"),
        Entry(image: "beer", tint: AppColor.warning, keywords: "beer|öl|lager|ipa|cider"),
        Entry(image: "wine", tint: AppColor.destructive, keywords: "wine|vin|prosecco|champagne"),
        Entry(image: "soft-drink", tint: AppColor.accentPrimary,
              keywords: "soda|läsk|cola|juice|saft|energy|shake|smoothie|sprite|fanta|pepsi|nocco"),
        Entry(image: "water", tint: AppColor.macroWater, keywords: "=water|=vatten|mineralvatten"),
        Entry(image: "berries", tint: AppColor.destructive,
              keywords: "strawberry|strawberries|jordgubb|jordgubbar|hallon|raspberry|raspberries|berry|berries|bär|blåbär|blueberry|blueberries|lingon"),
        Entry(image: "banana", tint: AppColor.warning, keywords: "banana|bananas|banan|bananer"),
        Entry(image: "apple", tint: AppColor.destructive, keywords: "apple|apples|äpple|äpplen|päron|pear"),
        Entry(image: "orange", tint: AppColor.warning,
              keywords: "orange|oranges|apelsin|clementin|mandarin|citrus|lemon|citron"),
        Entry(image: "grapes", tint: AppColor.metricSleep, keywords: "grape|grapes|druva|druvor|russin|raisin"),
        Entry(image: "tropical-fruit", tint: AppColor.warning, keywords: "pineapple|ananas|mango|melon|watermelon|vattenmelon|kiwi"),
        Entry(image: "avocado", tint: AppColor.success, keywords: "avocado|avokado|guacamole"),
        Entry(image: "carrot", tint: AppColor.warning, keywords: "carrot|carrots|morot|morötter"),
        Entry(image: "tomato", tint: AppColor.destructive, keywords: "tomato|tomatoes|tomat|tomater|ketchup"),
        Entry(image: "potato", tint: AppColor.macroCarbs,
              keywords: "potato|potatoes|potatis|pommes|fries|mos|sweet potato|sötpotatis"),
        Entry(image: "vegetables", tint: AppColor.success,
              keywords: "broccoli|kål|spinach|spenat|salad|sallad|vegetable|vegetables|grönsak|grönsaker|kale|ärtor|peas|bönor|beans|linser|lentils|gurka|cucumber|paprika"),
        Entry(image: "dumplings", tint: AppColor.macroCarbs, keywords: "gyoza|dumpling|dumplings"),
        // Last: Swedish "glass" (ice cream) is also the English serving
        // word, so "Glass of milk" and "Glass noodles" match their food first.
        Entry(image: "ice-cream", tint: AppColor.macroWater, keywords: "=glass"),
    ]
}

/// A food's picture at a fixed size: the product cut out of its photo on
/// the food's own tint, the whole photo on a white card when Vision found
/// no clean edge, the plate of the library recipe it was logged from,
/// else its `FoodArtwork`.
///
/// A diary entry only remembers its barcode, so `barcode` looks the
/// packshot up in the scan cache when no `imageURL` is given.
struct FoodThumbnail: View {
    let name: String
    let imageURL: URL?
    let barcode: String?
    let size: CGFloat

    @State private var photo: ProductPhoto?

    init(name: String, imageURL: URL? = nil, barcode: String? = nil, size: CGFloat = 44) {
        self.name = name
        self.imageURL = imageURL
        self.barcode = barcode
        self.size = size
        _photo = State(initialValue: imageURL.flatMap(ProductPhotoStore.shared.cached))
    }

    var body: some View {
        Group {
            if let photo {
                picture(photo)
            } else if let recipe = RecipeLibraryEngine.recipe(named: name) {
                RecipeCutout(recipe: recipe)
                    .padding(size * 0.06)
                    .background { tint(RecipeImage.artwork(for: recipe).tint) }
            } else {
                artwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
        .appAnimation(AppAnimation.fadeIn, value: photo?.isCutout)
        .task(id: [imageURL?.absoluteString, barcode]) {
            guard let url = await resolvedURL() else {
                photo = nil
                return
            }
            let loaded = await ProductPhotoStore.shared.photo(for: url)
            // A shared load ignores this task's cancellation, so a
            // superseded URL could otherwise land after the current one.
            guard !Task.isCancelled else { return }
            photo = loaded
        }
        .accessibilityHidden(true)
    }

    private func resolvedURL() async -> URL? {
        if let imageURL { return imageURL }
        guard let barcode else { return nil }
        return await BarcodeProductCache.shared.read(barcode: barcode)?.imageURL
    }

    /// A cut-out sits on the same tint as the artwork so a row of them
    /// reads as one set; a whole packshot comes on any background, so it
    /// gets a white card with a little margin instead.
    private func picture(_ photo: ProductPhoto) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFit()
            .padding(size * (photo.isCutout ? 0.12 : 0.1))
            .frame(width: size, height: size)
            .background {
                if photo.isCutout {
                    tint(FoodArtwork.match(name).tint)
                } else {
                    AppColor.onAccent
                }
            }
            .transition(.opacity)
    }

    private var artwork: some View {
        let art = FoodArtwork.match(name)
        return FoodArtworkImage(artwork: art)
            .padding(size * 0.1)
            .frame(width: size, height: size)
            .background { tint(art.tint) }
    }

    private func tint(_ color: Color) -> some View {
        LinearGradient(
            colors: [color.opacity(0.28), color.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A food's studio cut-out, or a fork-and-knife glyph in its tint until the
/// asset is in the catalog.
struct FoodArtworkImage: View {
    let artwork: FoodArtwork

    var body: some View {
        if let image = UIImage(named: artwork.assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "fork.knife")
                .resizable()
                .scaledToFit()
                .padding(4)
                .foregroundStyle(artwork.tint)
        }
    }
}
