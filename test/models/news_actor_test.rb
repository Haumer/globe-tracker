require "test_helper"

class NewsActorTest < ActiveSupport::TestCase
  test "valid creation" do
    actor = NewsActor.create!(canonical_key: "us-gov", name: "US Government", actor_type: "state")
    assert actor.persisted?
  end

  test "canonical_key is required" do
    r = NewsActor.new(name: "Test", actor_type: "state")
    assert_not r.valid?
    assert_includes r.errors[:canonical_key], "can't be blank"
  end

  test "name is required" do
    r = NewsActor.new(canonical_key: "test", actor_type: "state")
    assert_not r.valid?
    assert_includes r.errors[:name], "can't be blank"
  end

  test "actor_type is required" do
    r = NewsActor.new(canonical_key: "test", name: "Test")
    assert_not r.valid?
    assert_includes r.errors[:actor_type], "can't be blank"
  end

  test "has_many news_claim_actors" do
    actor = NewsActor.create!(canonical_key: "test-actor", name: "Test", actor_type: "org")
    assert_respond_to actor, :news_claim_actors
  end

  test "has_many news_claims through news_claim_actors" do
    actor = NewsActor.create!(canonical_key: "test-actor2", name: "Test", actor_type: "org")
    assert_respond_to actor, :news_claims
  end

  test "has_many ontology_entity_links" do
    actor = NewsActor.create!(canonical_key: "test-actor3", name: "Test", actor_type: "org")
    assert_respond_to actor, :ontology_entity_links
  end
end
