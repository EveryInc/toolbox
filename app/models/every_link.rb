# Outbound links to Every's own site, Vibe Checks and articles. They are set by an
# admin or in the catalog and rendered as links, so they must be https on a host we
# control: VIBE_CHECK_HOSTS (comma separated) or these. tag adds Toolbox's UTM
# parameters, so Every can see the reader came from Toolbox.
module EveryLink
  DEFAULT_HOSTS = %w[every.to checks.every.to].freeze
  UTM = { "utm_source" => "toolbox", "utm_medium" => "referral" }.freeze

  module_function

  def hosts
    ENV["VIBE_CHECK_HOSTS"].to_s.split(",").map { |host| host.strip.downcase }.compact_blank.presence || DEFAULT_HOSTS
  end

  # https, no credentials, the default port, and a host that is exactly an allowed one:
  # no suffix or wildcard match, so "every.to.evil.com" and "evil-every.to" fail.
  def allowed?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.port == uri.default_port && hosts.include?(uri.host.to_s.downcase)
  rescue URI::InvalidURIError
    false
  end

  # The link with Toolbox's UTM parameters in place of any it had; campaign is where it was shown.
  def tag(url, campaign:)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query.to_s).reject { |key, _| key.start_with?("utm_") }
    uri.query = URI.encode_www_form(params + UTM.merge("utm_campaign" => campaign).to_a)
    uri.to_s
  end
end
