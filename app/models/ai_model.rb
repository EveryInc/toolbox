# A model people pick inside a tool: Claude Opus 5.5, GPT-6 Astra, Veo 4.
class AiModel < ApplicationRecord
  include CatalogItem

  # Vibe Check links are set by an admin and rendered as outbound links (EveryLink).
  DEFAULT_VIBE_CHECK_HOSTS = EveryLink::DEFAULT_HOSTS

  normalizes :vibe_check_url, with: ->(url) { url.strip.presence }

  validates :vibe_check_url, length: { maximum: 2000 }
  validate :vibe_check_url_is_allowed

  # A model is listed as a launch when it has a release date and a Vibe Check link.
  scope :launched, -> { approved.where.not(released_on: nil).where.not(vibe_check_url: nil) }

  class << self
    def vibe_check_hosts = EveryLink.hosts

    def vibe_check_url_allowed?(value) = EveryLink.allowed?(value)
  end

  # The link to render. Checked again here so a value written past validation
  # (the console, a bulk update) never becomes a link on a page or in tool output.
  def vibe_check_link
    vibe_check_url if self.class.vibe_check_url_allowed?(vibe_check_url)
  end

  def kind = "model"

  private

  def vibe_check_url_is_allowed
    return if vibe_check_url.blank? || self.class.vibe_check_url_allowed?(vibe_check_url)

    errors.add(:vibe_check_url, "must be an https link on #{self.class.vibe_check_hosts.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}")
  end
end
