import SwiftUI

/// The picture a food gets when it has no product photo: an emoji for
/// what it is, read from its name in English or Swedish, on a tile in
/// a matching colour. Every food in the library, the diary and the
/// scanners then has an image, not a grey box.
struct FoodArtwork: Equatable {
    let emoji: String
    let tint: Color

    static let fallback = FoodArtwork(emoji: "🍽️", tint: AppColor.accentPrimary)

    static func match(_ name: String) -> FoodArtwork {
        let lowered = name.lowercased()
        let words = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for entry in catalog where entry.keywords.contains(where: { matches($0, words: words, text: lowered) }) {
            return FoodArtwork(emoji: entry.emoji, tint: entry.tint)
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
        let emoji: String
        let tint: Color
        let keywords: [String]

        /// `keywords` is "|"-separated, so the catalog stays one flat
        /// literal the compiler can type-check quickly. Split once here;
        /// `catalog` is a static let, so this runs once per entry.
        init(emoji: String, tint: Color, keywords: String) {
            self.emoji = emoji
            self.tint = tint
            self.keywords = keywords.split(separator: "|").map(String.init)
        }
    }

    /// Most specific first: "chocolate milk" is chocolate, "fish burger"
    /// is a burger.
    private static let catalog: [Entry] = [
        Entry(emoji: "🍬", tint: AppColor.destructive,
              keywords: "candy|godis|gummy|gummies|bilar|ferrari|lakrits|licorice|sweets|skumgodis|geléhall|marshmallow"),
        Entry(emoji: "🍫", tint: AppColor.macroFat,
              keywords: "chocolate|choklad|cocoa|kakao|marabou|snickers|twix|kitkat"),
        Entry(emoji: "🍦", tint: AppColor.macroWater,
              keywords: "ice cream|gelato|sorbet"),
        Entry(emoji: "🍪", tint: AppColor.macroCarbs,
              keywords: "cookie|kaka|kakor|kex|biscuit|digestive|brownie"),
        Entry(emoji: "🍰", tint: AppColor.macroCarbs,
              keywords: "cake|tårta|bakelse|muffin|bulle|kanelbulle|cheesecake|donut|munk"),
        Entry(emoji: "🍿", tint: AppColor.warning,
              keywords: "chips|popcorn|crisps|snacks|nachos|ostbågar"),
        Entry(emoji: "🥜", tint: AppColor.macroFat,
              keywords: "nut|nuts|nöt|nötter|peanut|jordnöt|almond|mandel|cashew|walnut|valnöt"),
        Entry(emoji: "🍕", tint: AppColor.destructive, keywords: "pizza"),
        Entry(emoji: "🍔", tint: AppColor.macroProtein, keywords: "burger|hamburgare|hamburger"),
        Entry(emoji: "🌮", tint: AppColor.warning, keywords: "taco|tacos|burrito|wrap|quesadilla"),
        Entry(emoji: "🍣", tint: AppColor.macroWater, keywords: "sushi|maki|nigiri|poke"),
        Entry(emoji: "🍜", tint: AppColor.macroCarbs, keywords: "ramen|noodle|noodles|nudlar|glassnudlar|pho|soup|soppa"),
        Entry(emoji: "🍝", tint: AppColor.macroCarbs, keywords: "pasta|spaghetti|penne|lasagne|lasagna|makaroner|fusilli"),
        Entry(emoji: "🍚", tint: AppColor.macroCarbs, keywords: "rice|ris|risotto|basmati|jasminris"),
        Entry(emoji: "🥣", tint: AppColor.macroCarbs,
              keywords: "oat|oats|havre|havregryn|gröt|porridge|müsli|muesli|granola|cereal|flingor"),
        Entry(emoji: "🍞", tint: AppColor.macroCarbs,
              keywords: "bread|bröd|toast|bagel|knäcke|limpa|fralla|baguette|tortilla|pita"),
        Entry(emoji: "🥓", tint: AppColor.macroProtein, keywords: "bacon"),
        Entry(emoji: "🌭", tint: AppColor.macroProtein, keywords: "sausage|korv|hotdog|chorizo|salami"),
        Entry(emoji: "🍗", tint: AppColor.macroProtein,
              keywords: "chicken|kyckling|karaage|turkey|kalkon|wings"),
        Entry(emoji: "🥩", tint: AppColor.macroProtein,
              keywords: "beef|nötkött|biff|steak|meat|kött|köttfärs|fläsk|pork|mince|lamm|lamb|skinka|ham"),
        Entry(emoji: "🐟", tint: AppColor.macroWater,
              keywords: "fish|fisk|salmon|lax|tuna|tonfisk|torsk|cod|sill|makrill|mackerel"),
        Entry(emoji: "🍤", tint: AppColor.warning, keywords: "shrimp|räkor|räka|prawn|prawns|scampi"),
        Entry(emoji: "🥚", tint: AppColor.warning, keywords: "egg|eggs|ägg|omelett|omelette"),
        Entry(emoji: "🧀", tint: AppColor.warning,
              keywords: "cheese|ost|cheddar|mozzarella|parmesan|brie|feta|halloumi"),
        Entry(emoji: "🧈", tint: AppColor.warning, keywords: "butter|smör|margarine|bregott"),
        Entry(emoji: "🫒", tint: AppColor.success, keywords: "olive|oliv|oil|olja|rapsolja"),
        Entry(emoji: "🥛", tint: AppColor.macroWater,
              keywords: "milk|mjölk|skummjölk|yoghurt|yogurt|kvarg|quark|filmjölk|cottage|skyr|fil|kefir"),
        Entry(emoji: "🍵", tint: AppColor.success, keywords: "tea|te|matcha|chai"),
        Entry(emoji: "☕", tint: AppColor.macroFat,
              keywords: "coffee|kaffe|latte|espresso|cappuccino|americano|flat white"),
        Entry(emoji: "🍺", tint: AppColor.warning, keywords: "beer|öl|lager|ipa|cider"),
        Entry(emoji: "🍷", tint: AppColor.destructive, keywords: "wine|vin|prosecco|champagne"),
        Entry(emoji: "🥤", tint: AppColor.accentPrimary,
              keywords: "soda|läsk|cola|juice|saft|energy|shake|smoothie|sprite|fanta|pepsi|nocco"),
        Entry(emoji: "💧", tint: AppColor.macroWater, keywords: "=water|=vatten|mineralvatten"),
        Entry(emoji: "🍓", tint: AppColor.destructive,
              keywords: "strawberry|strawberries|jordgubb|jordgubbar|hallon|raspberry|raspberries|berry|berries|bär|blåbär|blueberry|blueberries|lingon"),
        Entry(emoji: "🍌", tint: AppColor.warning, keywords: "banana|bananas|banan|bananer"),
        Entry(emoji: "🍎", tint: AppColor.destructive, keywords: "apple|apples|äpple|äpplen|päron|pear"),
        Entry(emoji: "🍊", tint: AppColor.warning,
              keywords: "orange|oranges|apelsin|clementin|mandarin|citrus|lemon|citron"),
        Entry(emoji: "🍇", tint: AppColor.metricSleep, keywords: "grape|grapes|druva|druvor|russin|raisin"),
        Entry(emoji: "🍍", tint: AppColor.warning, keywords: "pineapple|ananas|mango|melon|watermelon|vattenmelon|kiwi"),
        Entry(emoji: "🥑", tint: AppColor.success, keywords: "avocado|avokado|guacamole"),
        Entry(emoji: "🥕", tint: AppColor.warning, keywords: "carrot|carrots|morot|morötter"),
        Entry(emoji: "🍅", tint: AppColor.destructive, keywords: "tomato|tomatoes|tomat|tomater|ketchup"),
        Entry(emoji: "🥔", tint: AppColor.macroCarbs,
              keywords: "potato|potatoes|potatis|pommes|fries|mos|sweet potato|sötpotatis"),
        Entry(emoji: "🥦", tint: AppColor.success,
              keywords: "broccoli|kål|spinach|spenat|salad|sallad|vegetable|vegetables|grönsak|grönsaker|kale|ärtor|peas|bönor|beans|linser|lentils|gurka|cucumber|paprika"),
        Entry(emoji: "🥟", tint: AppColor.macroCarbs, keywords: "gyoza|dumpling|dumplings"),
        // Last: Swedish "glass" (ice cream) is also the English serving
        // word, so "Glass of milk" and "Glass noodles" match their food first.
        Entry(emoji: "🍦", tint: AppColor.macroWater, keywords: "=glass"),
    ]
}

/// A food's picture at a fixed size: the product cut out of its photo on
/// the food's own tint, the whole photo on a white card when Vision found
/// no clean edge, else its `FoodArtwork`.
struct FoodThumbnail: View {
    let name: String
    let imageURL: URL?
    let size: CGFloat

    @State private var photo: ProductPhoto?

    init(name: String, imageURL: URL? = nil, size: CGFloat = 44) {
        self.name = name
        self.imageURL = imageURL
        self.size = size
        _photo = State(initialValue: imageURL.flatMap(ProductPhotoStore.shared.cached))
    }

    var body: some View {
        Group {
            if let photo {
                picture(photo)
            } else {
                artwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
        .appAnimation(AppAnimation.fadeIn, value: photo?.isCutout)
        .task(id: imageURL) {
            guard let imageURL else {
                photo = nil
                return
            }
            let loaded = await ProductPhotoStore.shared.photo(for: imageURL)
            // A shared load ignores this task's cancellation, so a
            // superseded URL could otherwise land after the current one.
            guard !Task.isCancelled else { return }
            photo = loaded
        }
        .accessibilityHidden(true)
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
        return Text(art.emoji)
            .font(AppFont.scaled(size >= 52 ? 24 : 20))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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
