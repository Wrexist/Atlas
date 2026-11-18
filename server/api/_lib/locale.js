/**
 * The user's locale as a plain language/region tag, safe to put in a prompt.
 *
 * The scan and summary routes interpolate the app's locale into the model's
 * prompt. iOS identifiers can carry keywords (`sv_SE@rg=sezzzz`,
 * `en_US@calendar=japanese`); only the language and region matter, so the
 * keywords are dropped. Anything else that isn't a short tag falls back to
 * en_US: an uncapped subtag count let `en-ignore-previous-instructions` through.
 */
// Language plus at most two subtags (`zh_Hans_CN`), so 21 characters at most.
const TAG = /^[A-Za-z]{2,3}(?:[_-][A-Za-z0-9]{2,8}){0,2}$/;

export function localeTag(raw) {
  const base = String(raw ?? '').split('@')[0];
  return TAG.test(base) ? base : 'en_US';
}
