# Maps

`maps-cli` searches places, reads place details and computes routes through the private
GeoServices framework (no MapKit). Every command is also an MCP tool in `maps-cli mcp`; see
`maps-cli --help` and `maps-cli <command> --help`.

```sh
maps-cli search 'coffee' --near 'Haifa' --limit 5
maps-cli nearby pharmacy --near 32.79,34.99 --radius 800
maps-cli place 'Louvre Museum'               # address, phone, website, category, hours, rating
maps-cli reverse 32.8191,34.9983
maps-cli route --from 'Haifa' --to 'Acre' --mode cycling
maps-cli eta --from 'Louvre' --to 'Eiffel Tower' --mode driving --mode transit --arrive-by 'tomorrow 9:00'
```

- **Places** are a name or address, `lat,lon`, or a `geo:<provider>:<muid>` id from an earlier
  result. A name resolves to Apple Maps' best match and the result always echoes it. A route's
  destination is ranked near its start. `near` defaults to `maps.near` in
  `~/.config/gesher/config.json`.
- **Bias.** `near` is sent as the request's device location, as the Maps app does. With a bias
  the service sometimes ranks a far-away namesake of a landmark first, so the unbiased best match
  is also fetched and put first when it is closer. `nearby` filters to `radius` and sorts by
  straight-line distance.
- **Times.** `departAt`/`arriveBy` set the native route timepoint. Transit returns the scheduled
  departure and arrival; for other modes the other end is the timepoint plus or minus the
  duration. Times are output with the place's UTC offset.
- **Saved places.** Favorites, guides and recents live in Maps' private CloudKit sync store, with
  no stable interface and a schema that changes with Maps; they are not read.
- **Not available from GeoServices here:** transit distance and per-leg transit steps, live
  traffic provenance, reviews text. A failed mode is `route_service_error` with the service's
  reason (for example cycling `OUT_OF_COVERAGE`); nothing is estimated.
