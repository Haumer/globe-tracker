namespace :places do
  desc "Recompute normalized_name on places and place_aliases"
  task normalize: :environment do
    # Place.normalize_name used to transliterate, so "São Paulo" was stored as
    # "sao paulo". It now preserves Unicode, meaning a headline saying
    # "São Paulo" normalizes to "são paulo" and no longer matches the stored
    # row. Latin-only names are unaffected, so this touches very few rows --
    # but the ones it touches are major cities that would otherwise silently
    # degrade to a country centroid. Run this with any deploy of the
    # normalization change.
    places = 0
    Place.find_each do |place|
      normalized = Place.normalize_name(place.name)
      next if normalized == place.normalized_name || normalized.blank?

      place.update_columns(normalized_name: normalized)
      places += 1
    end

    aliases = 0
    PlaceAlias.find_each do |place_alias|
      normalized = Place.normalize_name(place_alias.name)
      next if normalized == place_alias.normalized_name || normalized.blank?

      # A recomputed value can collide with a sibling alias that already holds
      # it; the unique index on [place_id, normalized_name] would reject the
      # update, and the duplicate is redundant anyway.
      if PlaceAlias.where(place_id: place_alias.place_id, normalized_name: normalized)
                   .where.not(id: place_alias.id).exists?
        place_alias.destroy
      else
        place_alias.update_columns(normalized_name: normalized)
      end
      aliases += 1
    end

    puts "Renormalized #{places} places and #{aliases} aliases"
  end

  desc "Import the GeoNames cities5000 gazetteer (PATH=/path/to/cities5000.txt)"
  task import_geonames: :environment do
    path = ENV["PATH_TO_GEONAMES"] || ENV["GEONAMES_PATH"]
    abort "Set GEONAMES_PATH=/path/to/cities5000.txt (see #{GeonamesImportService::SOURCE_URL})" if path.blank?
    abort "No such file: #{path}" unless File.exist?(path)

    result = GeonamesImportService.import!(path: path)
    puts "Imported #{result.fetch(:places)} places and #{result.fetch(:aliases)} aliases"
    puts "Run `rails places:normalize` afterwards if the normalization rules changed."
  end
end
