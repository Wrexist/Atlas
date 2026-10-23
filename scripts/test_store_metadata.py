"""Regression checks for check-store-metadata.py, so it cannot go blind silently."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("store", Path(__file__).with_name("check-store-metadata.py"))
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)

PRODUCTS = [("Atlas Pro Monthly", "$9.99 / mo"), ("Atlas Pro Annual", "$49.99 / yr")]

TERMS = """SUBSCRIPTION TERMS
Atlas Pro Monthly ($9.99, renews monthly) and Atlas Pro Annual ($49.99, renews
yearly) are auto-renewable.
"""

MARKETING = "PRO\nMonthly $9.99 · Annual $49.99 · renews monthly\n\n——\n\n"


class SubscriptionTermsTests(unittest.TestCase):
    def test_complete_terms_block_with_wrapped_period_passes(self):
        self.assertEqual(store.subscription_terms_problems(MARKETING + TERMS, PRODUCTS), [])

    def test_dropped_annual_period_is_reported(self):
        description = MARKETING + TERMS.replace("renews\nyearly", "billed\nonce a year")
        problems = store.subscription_terms_problems(description, PRODUCTS)
        self.assertEqual(problems, ["Atlas Pro Annual: 'renews yearly' missing from SUBSCRIPTION TERMS"])

    def test_dropped_title_is_reported(self):
        description = MARKETING + TERMS.replace("Atlas Pro Annual", "The annual plan")
        problems = store.subscription_terms_problems(description, PRODUCTS)
        self.assertEqual(problems, ["Atlas Pro Annual: title missing from SUBSCRIPTION TERMS"])

    def test_missing_terms_block_fails_even_when_prices_appear_elsewhere(self):
        problems = store.subscription_terms_problems(MARKETING, PRODUCTS)
        self.assertEqual(problems, ["the description has no SUBSCRIPTION TERMS block"])

    def test_price_outside_the_terms_block_does_not_count(self):
        description = MARKETING + TERMS.replace("$49.99", "the listed price")
        problems = store.subscription_terms_problems(description, PRODUCTS)
        self.assertEqual(problems, ["Atlas Pro Annual: price $49.99 / yr missing from SUBSCRIPTION TERMS"])

    def test_terms_block_ends_at_the_next_divider(self):
        description = TERMS.replace("Atlas Pro Annual", "The annual plan") + "\n——\n\nAtlas Pro Annual is great.\n"
        problems = store.subscription_terms_problems(description, PRODUCTS)
        self.assertEqual(problems, ["Atlas Pro Annual: title missing from SUBSCRIPTION TERMS"])

    def test_real_listing_passes(self):
        md = store.METADATA.read_text()
        description = store.fenced_block(store.section(md, "Description"))
        self.assertEqual(store.subscription_terms_problems(description, store.auto_renewable_products(md)), [])


if __name__ == "__main__":
    unittest.main()
