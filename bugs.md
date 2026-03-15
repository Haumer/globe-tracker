# Bugs & Issues

## Satellite Connections Duplicates
- Clicking a satellite over Ukraine shows ~20 ground events with the same name repeated
- Connections API likely returning duplicate entries or not deduplicating by event name

## Weather Satellites Connected to War Events
- Weather satellites shouldn't show connections to conflict/war events
- Need to filter connection types by satellite category (weather sats → weather events only)

## GPS Jamming Always Displayed
- GPS jamming layer appears to be constantly shown even when not toggled on
- Check if jamming entities are being cleared properly when layer is toggled off
