module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_user
    end

    private

    def find_user
      # Allow anonymous connections for public broadcasts (earthquakes, conflicts).
      # Signed-in users keep their normal Warden/cookie-backed session on /cable.
      # Signed-in users also get per-user alert channel.
      if (user = env["warden"]&.user)
        user
      elsif (user_id = cookies.encrypted[:user_id])
        User.find_by(id: user_id)
      end
    end
  end
end
