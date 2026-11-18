import test from 'node:test';
import assert from 'node:assert/strict';
import { localeTag } from '../api/_lib/locale.js';

test('test_languageAndRegion_isKept', () => {
  assert.equal(localeTag('sv_SE'), 'sv_SE');
  assert.equal(localeTag('zh-Hans-CN'), 'zh-Hans-CN');
});

test('test_keywords_areDropped', () => {
  assert.equal(localeTag('sv_SE@calendar=gregorian;rg=sezzzz'), 'sv_SE');
});

test('test_wordsShapedLikeSubtags_fallBackToEnUS', () => {
  assert.equal(localeTag('en-ignore-previous-instructions'), 'en_US');
  assert.equal(localeTag('en-ignore-all-rules'), 'en_US');
});

test('test_missingOrMalformed_fallsBackToEnUS', () => {
  for (const raw of [undefined, null, '', 'not a locale!', 42, { locale: 'sv' }]) {
    assert.equal(localeTag(raw), 'en_US');
  }
});
