# JsonAttribute type coercion implementation

## 概要

`app/models/concerns/json_attribute.rb` の `define_json_attributes` で定義されるスキーマは `type` を指定しているが、現在のgetter実装は `data[key.to_s]` をそのまま返すのみで、型変換を一切おこなっていない。

JQUANTS APIからは文字列として数値が入る場合があり、EDINET XBRLパーサーからは整数として入る場合がある。同じカラムに異なる型の値が混在すると、後続の計算で比較演算やソートが正しく動作しない。

## 対象ファイル

- `app/models/concerns/json_attribute.rb`
- `spec/models/concerns/json_attribute_spec.rb`

## 実装内容

1. `define_json_attributes` のgetter生成部分で、スキーマの `type` に基づいた型変換をおこなう
   - `type: :integer` → `Integer(value)` (nilの場合はnil)
   - `type: :decimal` → `BigDecimal(value.to_s)` (nilの場合はnil)
   - `type: :string` → `value.to_s` (nilの場合はnil)
2. setter側でも型変換を適用し、JSON保存時点で型が統一されるようにする
3. 型変換失敗時は `nil` を返し、ログに警告を出力する

## テスト

- 文字列 "12345" が integer型のgetterで Integer 12345 を返すこと
- 文字列 "123.45" が decimal型のgetterで BigDecimal を返すこと
- nil値がそのまま nil を返すこと
- 不正値（"abc" を integer型で）が nil を返すこと

## 影響範囲

- FinancialValue, FinancialMetric, ApplicationProperty, DailyQuote, Company のすべてのJSON属性
- 既存データの読み出し時に暗黙的に型変換が適用されるため、破壊的変更にはならないが挙動が変わるケースの確認が必要
