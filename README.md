# Schap prijzen

Every morning a GitHub Action collects shelf prices for the Schap app and
publishes them on the `data` branch:

- `prices.json`: per supermarket, per product: price, name, pack size,
  product page, photo and (Albert Heijn) the current promotion.
- `price_history.json`: one price per store, product and day, 120 days.

The app reads them with
`--dart-define=PRICES_BASE=https://raw.githubusercontent.com/<owner>/<repo>/data`.

Sources: the open Checkjebon dataset (MIT), the Albert Heijn app's product
search, and product pages of jumbo.com and hoogvliet.com for photos. None of
the supermarkets offers this officially; it can break or be blocked.

Run it yourself: `dart pub get && dart run tool/sync_prices.dart`.
