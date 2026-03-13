class ApplicationController < ActionController::Base
  include BackgroundRefreshable
  include ApiHelpers

  before_action :authenticate_user!
end
