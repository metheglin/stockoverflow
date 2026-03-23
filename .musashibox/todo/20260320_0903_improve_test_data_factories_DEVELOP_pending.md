# TODO: FactoryBot導入とモデルファクトリ定義

## 概要

FactoryBotを導入し、全モデルのファクトリを定義することで、今後のテスト拡充の生産性を向上させる。

## 背景・課題

現在、テストでは以下のようにインスタンスを手動構築している:

```ruby
financial_value = FinancialValue.new(
  net_sales: 1000000,
  operating_income: 100000,
  net_income: 50000,
  total_assets: 2000000,
  ...
)
```

pending TODOが25件あり、その多くが実装時にテストを要する。テストのたびにモデルの全属性を手動指定するのは非効率であり、以下の問題がある:
- 属性の追加・変更時に全テストファイルの修正が必要
- テストで重要な属性と単なるフィラー値の区別がつきにくい
- 複数モデルの関連を含むテストデータの構築が煩雑

## 実装方針

### Gemfile追加

```ruby
group :development, :test do
  gem "factory_bot_rails"
end
```

### spec/support/factory_bot.rb

```ruby
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
```

### ファクトリ定義

#### spec/factories/companies.rb
- 基本属性: 証券コード、企業名、セクター、上場フラグ等
- trait: `:listed`, `:unlisted`

#### spec/factories/financial_values.rb
- 基本属性: 典型的な中堅企業の財務数値
- trait: `:profitable` (黒字), `:loss_making` (赤字)
- trait: `:with_cf_data` (キャッシュフロー付き)
- trait: `:with_extended_data` (data_json拡張属性付き)

#### spec/factories/financial_metrics.rb
- 基本属性: 典型的な成長企業の指標値
- trait: `:high_growth` (高成長), `:declining` (減収減益)
- trait: `:consecutive_growth` (連続増収増益)

#### spec/factories/financial_reports.rb
- 基本属性: 年次報告書
- trait: `:quarterly`, `:annual`, `:from_edinet`, `:from_jquants`

#### spec/factories/daily_quotes.rb
- 基本属性: 典型的な日次株価データ

#### spec/factories/application_properties.rb
- 基本属性: default kind
- trait: `:jquants_sync`, `:edinet_sync`

### 既存テストの移行

- 既存テストは現状のままでも動作するため、段階的に移行
- 新規テストからFactoryBotを使用する方針

## テスト

- ファクトリ自体のテスト: 各ファクトリが `build` で有効なインスタンスを生成できることの確認（lint test）

## 依存関係

- 他のTODOに先行して実装することで、以降の全DEVELOP TODOにおけるテスト記述効率が向上する
