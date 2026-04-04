# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
# In development, append a boot-scoped suffix so browser-cached digested assets
# are refreshed on each Puma restart during UI iteration.
base_asset_version = "1.0"
dev_boot_suffix = Rails.env.development? ? ".dev-#{Process.pid}" : ""
Rails.application.config.assets.version = "#{base_asset_version}#{dev_boot_suffix}"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )
Rails.application.config.assets.precompile += %w(bootstrap.min.js popper.js)
