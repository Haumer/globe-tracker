# A rotation cursor for pollers that work through their sources a slice at a
# time, derived from the clock rather than stored anywhere.
#
# Why not Rails.cache, which is what these services used before: the cursor was
# a read-increment-write counter, and `Rails.cache` is a NullStore in
# development and a per-process memory_store in production unless
# CACHE_BACKEND=redis is set. A NullStore read returns nil, so the counter was
# always `(nil || 0) % count` -- zero, on every single poll. Every rotating
# service was pinned to its first batch permanently: 215 of 253 sitemap
# publishers and 124 of 166 RSS feeds -- the whole Middle East, Africa, Asia
# and Oceania sections -- were never fetched at all. Under memory_store the
# counter does advance, but independently in each worker process and back to
# zero on every deploy, which biases towards the first batch rather than
# freezing on it.
#
# The clock needs no storage, so it cannot be dropped, is identical in every
# process without coordination, and survives restarts.
module BatchRotation
  # Which slice is due right now. `period` should match the poll cadence so
  # each poll advances exactly one step and a full rotation takes
  # `count * period`.
  def rotation_index(count, period:, now: Time.current)
    count = count.to_i
    return 0 if count <= 1

    (now.to_i / period.to_i) % count
  end

  # The slice of `items` due right now, sized so `count` slices cover them all.
  def rotation_slice(items, count, period:, now: Time.current)
    return items if count.to_i <= 1 || items.empty?

    size = (items.size.to_f / count).ceil
    idx = rotation_index(count, period: period, now: now)
    items.each_slice(size).to_a[idx] || []
  end
end
