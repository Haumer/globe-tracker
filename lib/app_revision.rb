require "digest/sha1"

module AppRevision
  module_function

  DEVELOPMENT_REVISION_GLOBS = [
    "app/javascript/**/*",
    "app/assets/stylesheets/**/*",
    "app/views/**/*",
    "config/importmap.rb",
    "lib/app_revision.rb",
  ].freeze

  def current
    return resolved_revision unless cacheable_revision?

    @current ||= resolved_revision
  end

  def cacheable_revision?
    Rails.env.production?
  end

  def resolved_revision
    explicit_revision || computed_revision
  end

  def explicit_revision
    ENV["APP_REVISION"].presence ||
      ENV["SOURCE_VERSION"].presence ||
      ENV["HEROKU_SLUG_COMMIT"].presence ||
      ENV["HEROKU_RELEASE_VERSION"].presence
  end

  def computed_revision
    importmap_digest = Rails.application.importmap.digest(resolver: ActionController::Base.helpers)
    return importmap_digest if cacheable_revision?

    Digest::SHA1.hexdigest([importmap_digest, development_source_fingerprint].join(":"))
  end

  def development_source_fingerprint
    root = Rails.root.to_s

    signatures = DEVELOPMENT_REVISION_GLOBS.flat_map do |pattern|
      Dir.glob(Rails.root.join(pattern).to_s).sort.filter_map do |path|
        next unless File.file?(path)

        stat = File.stat(path)
        relative_path = path.delete_prefix("#{root}/")
        "#{relative_path}:#{stat.size}:#{stat.mtime.to_f}"
      end
    end

    Digest::SHA1.hexdigest(signatures.join("|"))
  end
end
