# District-level (ADM2) boundaries for any country, from the geoBoundaries
# open dataset (gbOpen, CC-BY). Two hops: the catalog API names the current
# release, the release carries a simplified GeoJSON small enough to scan and
# serve. Both hops cache for a week -- district lines change on the cadence
# of censuses, not news cycles. A country without ADM2 (microstates, some
# territories) or an unreachable catalog resolves to [], and callers fall
# back to admin-1.
class GeoBoundariesService
  CACHE_TTL = 7.days

  class << self
    include HttpClient

    def adm2_features(iso3)
      code = iso3.to_s.strip.upcase
      return [] unless code.match?(/\A[A-Z]{3}\z/)

      # One retry only: a country with no ADM2 release 404s every time, and
      # the default retry ladder would spend seconds proving it.
      meta = http_get(
        URI("https://www.geoboundaries.org/api/current/gbOpen/#{code}/ADM2/"),
        cache_key: "geoboundaries:meta:adm2:#{code}:v1",
        cache_ttl: CACHE_TTL,
        retries: 1
      )
      url = meta.is_a?(Hash) && (meta["simplifiedGeometryGeoJSON"].presence || meta["gjDownloadURL"].presence)
      return [] unless url

      payload = http_get(
        URI(direct_url(url)),
        cache_key: "geoboundaries:adm2:#{code}:v1",
        cache_ttl: CACHE_TTL,
        read_timeout: 60
      )
      payload.is_a?(Hash) ? Array(payload["features"]) : []
    end

    private

    # The catalog hands out github.com/<org>/<repo>/raw/<ref>/<path> links and
    # the shared http client does not follow redirects. The obvious rewrite to
    # raw.githubusercontent.com is a trap: geoBoundaries stores its GeoJSON in
    # Git LFS, so that host serves the 131-byte pointer file, not the data.
    # media.githubusercontent.com is where the github.com redirect actually
    # lands and serves the real bytes. Any other URL shape passes through.
    def direct_url(url)
      url.sub(%r{\Ahttps://github\.com/([^/]+)/([^/]+)/raw/}, 'https://media.githubusercontent.com/media/\1/\2/')
    end
  end
end
