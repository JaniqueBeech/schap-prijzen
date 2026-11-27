# Schap prijzen

Every morning a GitHub Action collects shelf prices for the Schap app and
publishes them on the `data` branch:

- `prices.json`: per supermarket, per product: price, name, pack size,
  product page, photo and (Albert Heijn, Jumbo, Hoogvliet) the current
  promotion as `deal: {label, p, end}`.
- `price_history.json`: one price per store, product and day, 120 days.

The app reads them with
`--dart-define=PRICES_BASE=https://raw.githubusercontent.com/<owner>/<repo>/data`.

Sources: the open Checkjebon dataset (MIT), the Albert Heijn app's product
search, and the product pages of jumbo.com and hoogvliet.nl (shelf price,
photo, promotion). None of the supermarkets offers this officially; it can
break or be blocked.

Promotions are only published when the store states a price for buying one
item, valid today, in the shop: `p` stays the regular shelf price and
`deal.p` is the promotion price. Multi-buys ("2 voor 3,49", "1+1 gratis"),
per-weight prices, mix-and-match and online-only offers are skipped. The
rules are in `tool/promotions.dart`. PLUS is not covered yet: plus.nl renders
its products in the browser, so the page HTML has no prices.

Run it yourself: `dart pub get && dart run tool/sync_prices.dart`.
