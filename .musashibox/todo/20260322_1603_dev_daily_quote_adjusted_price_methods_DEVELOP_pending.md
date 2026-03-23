# DailyQuote 株価調整計算メソッドの追加

## 概要

`DailyQuote` モデルには `adjustment_factor` と `adjusted_close` カラムが存在するが、これらを活用して過去の株価を調整済みで取得するメソッドが存在しない。

バリュエーション指標（PER, PBR, PSR）の計算において、`CalculateFinancialMetricsJob#load_stock_price` は `close_price` をそのまま利用している。株式分割・併合があった場合、分割前後の株価をそのまま比較すると指標が不正確になる。

また将来的な技術指標（移動平均、ボラティリティ等）の算出においても、調整済み価格系列が不可欠である。

## 対象ファイル

- `app/models/daily_quote.rb`
- `spec/models/daily_quote_spec.rb`

## 実装内容

### インスタンスメソッド

1. `adjusted_open` - `open_price * (adjusted_close / close_price)` に相当する調整済み始値
2. `adjusted_high` - 調整済み高値
3. `adjusted_low` - 調整済み安値
4. `adjusted_volume` - `volume / adjustment_factor` に相当する調整済み出来高

### クラスメソッド

1. `load_adjusted_series(company_id:, from:, to:)` - 指定期間の調整済み株価系列を返す
   - 戻り値: `[{traded_on:, open:, high:, low:, close:, volume:}, ...]`
   - adjustment_factor を使って全期間を最新基準に調整

## テスト

- adjustment_factor = 2.0 の場合、adjusted_open が open_price の半分になること
- adjustment_factor = 1.0 の場合、調整済み価格が元の価格と一致すること
- adjusted_close が nil の場合のフォールバック動作
- load_adjusted_series が日付順に返すこと

## 備考

- `CalculateFinancialMetricsJob#load_stock_price` においても、取得した株価の `adjusted_close` を使うべきかの検討が必要
- JQUANTS から取得済みの `adjusted_close` をそのまま使えるため、自前計算と既存データの両方をサポートする設計とする
