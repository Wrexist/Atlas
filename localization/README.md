# Withheld translations

`Localizable.translated.xcstrings` is the full nine-language catalog —
170 keys in ar, de, es, fr, ja, ko, pt-BR, ru and zh-Hans, all complete.

It lives here, outside every target's source path, because those 170 keys
cover **45 of the app's 349 UI sentences (13%)**. Shipping the languages
would put all nine on the App Store listing while the other 87% of the app
rendered in English — dosing and safety copy included.

So the translations are withheld, not discarded.

## Restoring a language

1. Copy that language's `localizations` blocks into
   `Peptide/Resources/Localizable.xcstrings`.
2. Add it to `CFBundleLocalizations` in `project.yml`.
3. `python3 scripts/check-localization.py` gates it: a non-English language
   needs 80% UI coverage first. Raise coverage before restoring, not after.

The gate reads the shipped catalog, not a declaration — what Xcode compiles
into `.lproj` folders is what the App Store lists.
