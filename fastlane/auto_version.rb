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
# One exception fails closed: an expired or unsigned Apple agreement.
# The upload would be refused with the same error after a ~20 minute
# archive, so the run stops here with the fix spelled out instead.

require "rubygems"

module AutoVersion
  class AgreementMissing < StandardError; end

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
    raise AgreementMissing, e.message if agreement_missing?(e)

    warn "auto_version: App Store Connect lookup failed (#{e.class}: #{e.message}); using the floor"
    nil
  end

  def self.agreement_missing?(error)
    error.class.name.to_s.end_with?("ProgramLicenseAgreementUpdated") ||
      error.message.include?("required agreement is missing or has expired")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ceiling = AutoVersion.apple_ceiling
  rescue AutoVersion::AgreementMissing => e
    puts "::error::App Store Connect refused the API key: #{e.message} " \
         "The Account Holder must accept the updated agreement at " \
         "https://appstoreconnect.apple.com/business (Agreements), then re-run."
    exit 1
  end
  puts AutoVersion.pick(
    floor:   Gem::Version.new(ENV.fetch("AUTO_VERSION_FLOOR")),
    ceiling: ceiling,
    build:   Integer(ENV.fetch("BUILD"))
  )
end
