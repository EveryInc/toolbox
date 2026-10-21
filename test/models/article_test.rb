require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  # The real catalog: a bad article fails here in CI rather than vanishing from the page.
  test "every article in the catalog has a title, an Every link, known kinds and a known tool" do
    kinds = Catalog::Sync.data.fetch("categories").pluck("slug")
    tools = Catalog::Sync.data.fetch("tools").pluck("slug")

    assert_kind_of Array, Article.all
    Article.all.each do |article|
      assert article.title.present?, "an article needs a title"
      assert article.link, "#{article.title}: #{article.url} is not an https link on #{EveryLink.hosts.to_sentence}"
      assert article.kinds.any?, "#{article.title} is on no kind"
      assert_empty article.kinds - kinds, "#{article.title} names an unknown kind"
      assert_includes tools, article.tool, "#{article.title} names an unknown tool" if article.tool
    end
  end
end
