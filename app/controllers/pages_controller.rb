class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home, :sources, :about, :landing ]

  def home
  end

  def sources
    @sources = SourceCatalog.entries
  end

  def about
  end

  def landing
  end
end
