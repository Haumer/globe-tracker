require "test_helper"

class NewsSourceTest < ActiveSupport::TestCase
  test "valid creation" do
    source = NewsSource.create!(canonical_key: "reuters-src", name: "Reuters", source_kind: "publisher")
    assert source.persisted?
  end

  test "canonical_key is required" do
    r = NewsSource.new(name: "Test", source_kind: "publisher")
    assert_not r.valid?
    assert_includes r.errors[:canonical_key], "can't be blank"
  end

  test "name is required" do
    r = NewsSource.new(canonical_key: "test", source_kind: "publisher")
    assert_not r.valid?
    assert_includes r.errors[:name], "can't be blank"
  end

  test "source_kind is required" do
    r = NewsSource.new(canonical_key: "test", name: "Test")
    r.source_kind = nil
    assert_not r.valid?
    assert_includes r.errors[:source_kind], "can't be blank"
  end

  test "has_many news_articles" do
    source = NewsSource.create!(canonical_key: "src-arts", name: "Src", source_kind: "publisher")
    assert_respond_to source, :news_articles
  end

  test "has_many news_events" do
    source = NewsSource.create!(canonical_key: "src-evts", name: "Src", source_kind: "publisher")
    assert_respond_to source, :news_events
  end

  test "has_many ontology_entity_links" do
    source = NewsSource.create!(canonical_key: "src-links", name: "Src", source_kind: "publisher")
    assert_respond_to source, :ontology_entity_links
  end
end
