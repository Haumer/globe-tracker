module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_user
    end

    private

    def find_user
      # Allow anonymous connections for public broadcasts (earthquakes, conflicts)
      # Signed-in users also get per-user alert channel
      env["warden"]&.user
    end
  end
end
