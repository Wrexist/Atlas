# Picks the marketing version for a TestFlight run whose
# `marketing_version` input was left blank, and prints it.
#
# A hard-coded auto line (it used to be 1.2.<run_number>) falls behind
# the moment anyone uploads a higher version by hand, and the Fastfile
# guard then refuses every blank-input run. So the line is derived from
# what Apple already has instead:
#
#   <major>.<minor>.<run_number>, where major.minor is the higher of
#   AUTO_VERSION_FLOOR and the highest version at Apple (TestFlight
#   trains and the live App Store version). If that still isn't above
#   Apple's highest (a hand-made patch above run_number), the minor
#   goes up by one.
#
# Fail-open like the Fastfile guard: if App Store Connect can't be
# reached, the floor is used and the guard still checks the upload.

require "rubygems"

module AutoVersion
  def self.pick(floor:, ceiling:, build:)
    base = [floor, ceiling].compact.max
    major, minor = base.segments
    minor ||= 0
    candidate = Gem::Version.new("#{major}.#{minor}.#{build}")
    return candidate.to_s if ceiling.nil? || candidate > ceiling

    "#{major}.#{minor + 1}.#{build}"
  end

  def self.apple_ceiling
    require "spaceship"

    Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
      key_id:    ENV.fetch("ASC_KEY_ID"),
      issuer_id: ENV.fetch("ASC_ISSUER_ID"),
      key:       ENV.fetch("ASC_KEY_P8")
    )
    app = Spaceship::ConnectAPI::App.find("com.peptidesai.app")
    prerelease = Spaceship::ConnectAPI
                 .get_pre_release_versions(filter: { app: app.id }, limit: 200)
                 .all_pages
                 .flat_map(&:to_models)
                 .map(&:version)
    live = app.get_live_app_store_version&.version_string

    (prerelease + [live]).compact.map { |v| Gem::Version.new(v) }.max
  rescue StandardError => e
    warn "auto_version: App Store Connect lookup failed (#{e.class}: #{e.message}); using the floor"
    nil
  end
end

if $PROGRAM_NAME == __FILE__
  puts AutoVersion.pick(
    floor:   Gem::Version.new(ENV.fetch("AUTO_VERSION_FLOOR")),
    ceiling: AutoVersion.apple_ceiling,
    build:   Integer(ENV.fetch("BUILD"))
  )
end
