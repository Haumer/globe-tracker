class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home, :sources ]

  def home
  end

  def sources
  end
end
