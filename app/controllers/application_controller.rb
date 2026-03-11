class ApplicationController < ActionController::Base
  include BackgroundRefreshable

  before_action :authenticate_user!
end
