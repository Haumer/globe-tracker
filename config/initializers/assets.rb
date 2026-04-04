# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
boot_asset_suffix =
  if Rails.env.development?
    ENV["GT_DEV_ASSET_BOOT_VERSION"] ||= "#{Time.now.utc.to_i}-#{Process.pid}"
    ".dev-#{ENV.fetch("GT_DEV_ASSET_BOOT_VERSION")}"
  else
    ""
  end

Rails.application.config.assets.version = "1.2#{boot_asset_suffix}"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )
Rails.application.config.assets.precompile += %w(bootstrap.min.js popper.js)
