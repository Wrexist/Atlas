source "https://rubygems.org"

# Pin fastlane so every CI run resolves to the same toolchain. After
# changing this version, run `bundle install` locally and commit the
# updated Gemfile.lock alongside the Gemfile change.
gem "fastlane", "~> 2.220"

# fastlane 2.235's Play Store actions transitively `require "multi_json"`
# (via representable) without declaring it, so on Ruby 3.3+ the load fails
# with "multi_json is not part of the bundle". Declare it explicitly so
# `bundle install` always resolves it.
gem "multi_json"
