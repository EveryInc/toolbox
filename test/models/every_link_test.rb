require "test_helper"

class EveryLinkTest < ActiveSupport::TestCase
  test "allows only https links on an Every host, matched exactly" do
    assert EveryLink.allowed?("https://every.to/p/an-article")
    assert EveryLink.allowed?("https://checks.every.to/vibe-checks/claude-opus-5-5")
    assert_not EveryLink.allowed?("http://every.to/p/an-article")
    assert_not EveryLink.allowed?("https://every.to.evil.com/p")
    assert_not EveryLink.allowed?("https://user:pass@every.to/p")
    assert_not EveryLink.allowed?("not a url")
  end

  test "tag adds Toolbox's UTM, keeps other parameters, and replaces any UTM the link had" do
    assert_equal "https://every.to/p/a?utm_source=toolbox&utm_medium=referral&utm_campaign=personal-agents",
      EveryLink.tag("https://every.to/p/a", campaign: "personal-agents")
    assert_equal "https://every.to/p/a?ref=x&utm_source=toolbox&utm_medium=referral&utm_campaign=coding",
      EveryLink.tag("https://every.to/p/a?utm_source=newsletter&ref=x", campaign: "coding")
  end
end
