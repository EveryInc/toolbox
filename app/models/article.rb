# An Every article linked from the kinds of work it is about. Articles live in
# config/catalog.yml, not the database, and show beside the Vibe Checks in a kind's
# takes, tagged Article; tool (a slug, optional) gives the row its tile.
#
#   articles:
#     - { title: "How the team uses personal agents", url: "https://every.to/…", kinds: [personal-agents], tool: dots }
Article = Data.define(:title, :url, :kinds, :tool) do
  class << self
    # The catalog file to read; tests point it at one of their own.
    attr_writer :path

    def path = @path || Catalog::Sync::PATH
  end

  def self.all
    Array(Catalog::Sync.data(path)["articles"]).map { |attrs| new(title: attrs.fetch("title"), url: attrs.fetch("url"), kinds: Array(attrs.fetch("kinds")), tool: attrs["tool"]) }
  end

  # The articles about a kind whose link passes the allowlist, in catalog order.
  def self.about(category) = all.select { |article| article.kinds.include?(category.slug) && article.link }

  # Checked on every read, like a Vibe Check link, so a bad URL never becomes a link.
  def link
    url if EveryLink.allowed?(url)
  end
end
