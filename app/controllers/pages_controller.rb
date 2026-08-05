class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home, :sources, :about, :landing, :relationship_lens ]

  def home
  end

  def sources
    @sources = SourceCatalog.entries
  end

  def about
  end

  def landing
  end

  def relationship_lens
    @relationship_graph = RelationshipLensGraphService.build
  end
end
