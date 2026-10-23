# Withheld translations

The app ships English and Swedish. Swedish is translated in every target's
`Localizable.xcstrings` (app, widgets, Watch, Watch widgets).

`Localizable.translated.xcstrings` is a nine-language catalog —
170 keys in ar, de, es, fr, ja, ko, pt-BR, ru and zh-Hans, all complete.

It lives here, outside every target's source path, because those 170 keys
are a small fraction of the app's UI sentences. Shipping the languages would
put all nine on the App Store listing while most of the app rendered in
English — dosing and safety copy included.

So the translations are withheld, not discarded.

## Restoring a language

1. Translate the rest of the app's keys for that language, in every
   target catalog — the 170 here are a starting point, not a localization.
2. Copy its `localizations` blocks into each target's
   `Localizable.xcstrings`.
3. Add it to `CFBundleLocalizations` in `project.yml`.
4. `python3 scripts/check-localization.py` gates it: a shipped non-English
   language must translate 80% of the UI sentences, and every translation
   must keep its key's format specifiers.

The gate reads the shipped catalogs, not a declaration — what Xcode compiles
into `.lproj` folders is what the App Store lists.
