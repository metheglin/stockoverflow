# データベーススキーマ実装

## 概要

本プロジェクトのデータベーススキーマを実装する。マスターデータ層・分析指標層・アプリケーション管理層の3層構成で、EDINET/JQUANTS双方のデータを統合的に管理する。

## 前提知識

### データソース

- **EDINET API v2**: 有価証券報告書・四半期報告書等の開示書類。XBRL形式で詳細な財務データを取得可能
- **JQUANTS API v2**: 上場銘柄一覧・株価四本値・財務情報サマリー・決算発表予定日を提供

### 識別コード

- EDINETコード: `E` + 5桁数字（例: `E12345`）。企業ごとに一意
- 証券コード（JQUANTS）: 5桁文字列。一般的な4桁コード + 末尾`0`（例: `72030`）
- EDINET書類管理番号: 英数字8桁（例: `S100TDUA`）

---

## 実装タスク

### タスク1: JsonAttribute concern の実装

CLAUDE.mdのRails規約に従い、JSON型カラムにスキーマを適用してアクセスするための `JsonAttribute` concern を実装する。

#### ファイル: `app/models/concerns/json_attribute.rb`

```ruby
module JsonAttribute
  extend ActiveSupport::Concern

  class_methods do
    # JSON型カラムにスキーマを定義し、各属性へのアクセサを提供する
    #
    # 使用例:
    #   define_json_attributes :data_json, schema: {
    #     variant_name: { type: :string },
    #     bytesize: { type: :integer },
    #   }
    #
    #   record.variant_name       # => "thumbnail"
    #   record.variant_name = "x" # => セッターも利用可能
    #
    def define_json_attributes(column_name, schema:)
      # スキーマ定義をクラスレベルで保持
      class_attribute :"#{column_name}_schema", default: schema

      schema.each_key do |attr_name|
        define_method(attr_name) do
          (send(column_name) || {})[attr_name.to_s]
        end

        define_method(:"#{attr_name}=") do |value|
          json = send(column_name) || {}
          json[attr_name.to_s] = value
          send(:"#{column_name}=", json)
        end
      end
    end
  end
end
```

#### テスト: `spec/models/concerns/json_attribute_spec.rb`

- `define_json_attributes` で定義した属性のgetter/setterが正しく動作すること
- カラムがnilの場合にgetterがnilを返すこと
- setterで値を設定した場合にJSONカラムが更新されること

---

### タスク2: マイグレーション作成・実行

以下の順序でマイグレーションを作成する。

#### マイグレーション 2-1: `create_companies`

```ruby
create_table :companies do |t|
  t.string :edinet_code, null: true
  t.string :securities_code, null: true
  t.string :name, null: false
  t.string :name_english
  t.string :sector_17_code
  t.string :sector_17_name
  t.string :sector_33_code
  t.string :sector_33_name
  t.string :market_code
  t.string :market_name
  t.string :scale_category
  t.boolean :listed, null: false, default: true
  t.json :data_json
  t.timestamps
end

add_index :companies, :edinet_code, unique: true
add_index :companies, :securities_code, unique: true
add_index :companies, :listed
```

#### マイグレーション 2-2: `create_financial_reports`

```ruby
create_table :financial_reports do |t|
  t.references :company, null: false, foreign_key: true
  t.string :doc_id
  t.string :doc_type_code
  t.integer :report_type, null: false
  t.date :fiscal_year_start
  t.date :fiscal_year_end
  t.date :period_start
  t.date :period_end
  t.datetime :submitted_at
  t.date :disclosed_at
  t.integer :source, null: false
  t.json :data_json
  t.timestamps
end

add_index :financial_reports, :doc_id, unique: true
add_index :financial_reports, [:company_id, :fiscal_year_end, :report_type], name: "idx_fin_reports_company_year_type"
add_index :financial_reports, :fiscal_year_end
add_index :financial_reports, :disclosed_at
```

#### マイグレーション 2-3: `create_financial_values`

```ruby
create_table :financial_values do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_report, null: true, foreign_key: true
  t.integer :scope, null: false, default: 0
  t.integer :period_type, null: false
  t.date :fiscal_year_end, null: false

  # P/L
  t.bigint :net_sales
  t.bigint :operating_income
  t.bigint :ordinary_income
  t.bigint :net_income
  t.decimal :eps, precision: 15, scale: 2
  t.decimal :diluted_eps, precision: 15, scale: 2

  # B/S
  t.bigint :total_assets
  t.bigint :net_assets
  t.decimal :equity_ratio, precision: 7, scale: 2
  t.decimal :bps, precision: 15, scale: 2

  # C/F
  t.bigint :operating_cf
  t.bigint :investing_cf
  t.bigint :financing_cf
  t.bigint :cash_and_equivalents

  # 株式情報
  t.bigint :shares_outstanding
  t.bigint :treasury_shares

  # 拡張データ（配当、業績予想、非連結データ、XBRLの追加要素等）
  t.json :data_json

  t.timestamps
end

add_index :financial_values, [:company_id, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_fin_values_unique"
add_index :financial_values, :fiscal_year_end
```

#### マイグレーション 2-4: `create_financial_metrics`

```ruby
create_table :financial_metrics do |t|
  t.references :company, null: false, foreign_key: true
  t.references :financial_value, null: false, foreign_key: true
  t.integer :scope, null: false, default: 0
  t.integer :period_type, null: false
  t.date :fiscal_year_end, null: false

  # 成長性指標 (YoY, 小数で表現: 0.15 = 15%成長)
  t.decimal :revenue_yoy, precision: 10, scale: 4
  t.decimal :operating_income_yoy, precision: 10, scale: 4
  t.decimal :ordinary_income_yoy, precision: 10, scale: 4
  t.decimal :net_income_yoy, precision: 10, scale: 4
  t.decimal :eps_yoy, precision: 10, scale: 4

  # 収益性指標 (小数で表現: 0.12 = 12%)
  t.decimal :roe, precision: 10, scale: 4
  t.decimal :roa, precision: 10, scale: 4
  t.decimal :operating_margin, precision: 10, scale: 4
  t.decimal :ordinary_margin, precision: 10, scale: 4
  t.decimal :net_margin, precision: 10, scale: 4

  # CF指標
  t.bigint :free_cf
  t.boolean :operating_cf_positive
  t.boolean :investing_cf_negative
  t.boolean :free_cf_positive

  # 連続指標（この期末時点で何期連続か）
  t.integer :consecutive_revenue_growth, null: false, default: 0
  t.integer :consecutive_profit_growth, null: false, default: 0

  # 拡張指標（バリュエーション指標等。株価データが必要なためJSON管理）
  t.json :data_json

  t.timestamps
end

add_index :financial_metrics, [:company_id, :fiscal_year_end, :scope, :period_type], unique: true, name: "idx_fin_metrics_unique"
add_index :financial_metrics, :fiscal_year_end
add_index :financial_metrics, :consecutive_revenue_growth
add_index :financial_metrics, :consecutive_profit_growth
```

#### マイグレーション 2-5: `create_daily_quotes`

株価データ。バリュエーション指標（PER/PBR/PSR）の算出に必要。

```ruby
create_table :daily_quotes do |t|
  t.references :company, null: false, foreign_key: true
  t.date :traded_on, null: false
  t.decimal :open_price, precision: 12, scale: 2
  t.decimal :high_price, precision: 12, scale: 2
  t.decimal :low_price, precision: 12, scale: 2
  t.decimal :close_price, precision: 12, scale: 2
  t.bigint :volume
  t.bigint :turnover_value
  t.decimal :adjustment_factor, precision: 12, scale: 6
  t.decimal :adjusted_close, precision: 12, scale: 2
  t.json :data_json
  t.timestamps
end

add_index :daily_quotes, [:company_id, :traded_on], unique: true
add_index :daily_quotes, :traded_on
```

#### マイグレーション 2-6: `create_application_properties`

```ruby
create_table :application_properties do |t|
  t.integer :kind, null: false, default: 0
  t.json :data_json, null: false, default: "{}"
  t.timestamps
end

add_index :application_properties, :kind, unique: true
```

---

### タスク3: モデル実装

#### 3-1: `app/models/company.rb`

```ruby
class Company < ApplicationRecord
  has_many :financial_reports, dependent: :destroy
  has_many :financial_values, dependent: :destroy
  has_many :financial_metrics, dependent: :destroy
  has_many :daily_quotes, dependent: :destroy

  scope :listed, -> { where(listed: true) }
end
```

#### 3-2: `app/models/financial_report.rb`

```ruby
class FinancialReport < ApplicationRecord
  belongs_to :company
  has_one :financial_value

  enum :report_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
    semi_annual: 4,
    other: 9,
  }

  enum :source, {
    edinet: 0,
    jquants: 1,
    manual: 2,
  }
end
```

report_type の説明:
- `annual` (0): 有価証券報告書 (docTypeCode=120) / 通期決算
- `q1` (1): 第1四半期報告書 / 第1四半期決算
- `q2` (2): 第2四半期報告書 / 第2四半期決算
- `q3` (3): 第3四半期報告書 / 第3四半期決算
- `semi_annual` (4): 半期報告書 (docTypeCode=160)
- `other` (9): その他

source の説明:
- `edinet` (0): EDINET APIから取得
- `jquants` (1): JQUANTS APIから取得
- `manual` (2): 手動入力

#### 3-3: `app/models/financial_value.rb`

```ruby
class FinancialValue < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_report, optional: true
  has_one :financial_metric

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  define_json_attributes :data_json, schema: {
    # 配当実績
    dividend_per_share_annual: { type: :decimal },
    total_dividend_paid: { type: :integer },
    payout_ratio: { type: :decimal },
    # 業績予想
    forecast_net_sales: { type: :integer },
    forecast_operating_income: { type: :integer },
    forecast_ordinary_income: { type: :integer },
    forecast_net_income: { type: :integer },
    forecast_eps: { type: :decimal },
    # XBRL追加要素
    cost_of_sales: { type: :integer },
    gross_profit: { type: :integer },
    sga_expenses: { type: :integer },
    current_assets: { type: :integer },
    noncurrent_assets: { type: :integer },
    current_liabilities: { type: :integer },
    noncurrent_liabilities: { type: :integer },
    shareholders_equity: { type: :integer },
  }
end
```

scope の説明:
- `consolidated` (0): 連結決算
- `non_consolidated` (1): 個別決算

period_type の説明:
- `annual` (0): 通期（12ヶ月）
- `q1` (1): 第1四半期（3ヶ月累計）
- `q2` (2): 第2四半期（6ヶ月累計 / 中間期）
- `q3` (3): 第3四半期（9ヶ月累計）

#### 3-4: `app/models/financial_metric.rb`

```ruby
class FinancialMetric < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_value

  enum :scope, {
    consolidated: 0,
    non_consolidated: 1,
  }

  enum :period_type, {
    annual: 0,
    q1: 1,
    q2: 2,
    q3: 3,
  }

  define_json_attributes :data_json, schema: {
    # バリュエーション指標（株価データ連携後に算出）
    per: { type: :decimal },
    pbr: { type: :decimal },
    psr: { type: :decimal },
    dividend_yield: { type: :decimal },
    ev_ebitda: { type: :decimal },
  }
end
```

#### 3-5: `app/models/daily_quote.rb`

```ruby
class DailyQuote < ApplicationRecord
  belongs_to :company
end
```

#### 3-6: `app/models/application_property.rb`

```ruby
class ApplicationProperty < ApplicationRecord
  include JsonAttribute

  enum :kind, {
    default: 0,
    edinet_sync: 1,
    jquants_sync: 2,
  }

  define_json_attributes :data_json, schema: {
    last_synced_at: { type: :string },
    last_synced_date: { type: :string },
    sync_cursor: { type: :string },
  }
end
```

kind の説明:
- `default` (0): デフォルト。汎用メタデータ
- `edinet_sync` (1): EDINET連携の状態管理。最後に取得した日付等
- `jquants_sync` (2): JQUANTS連携の状態管理

---

### タスク4: テスト作成

テスティング規約に従い、モデル内のインスタンスメソッド・クラスメソッドのテストを記述する。バリデーション・スコープ・コールバックのテストは書かない。

#### 4-1: `spec/models/concerns/json_attribute_spec.rb`

JsonAttribute concern のテスト。テスト用の一時モデルを使って getter/setter の動作を検証する。

#### 4-2: 各モデルのテストファイル

現時点ではカスタムメソッドを定義していないモデルについてはテストファイルの作成のみとし、今後メソッドが追加された際にテストを追加する。

---

## 設計判断の根拠

### financial_values の構造選択: 固定カラム + JSON

- **固定カラム**: 売上高・営業利益・純利益・総資産・純資産・CF等の主要16項目は、ユースケースで頻繁に検索・ソート・比較の対象となるため、専用カラムとしてインデックスやSQLの恩恵を受けられるようにした
- **JSON (`data_json`)**: 配当情報・業績予想・非連結データ・XBRLの追加要素等は項目数が多く拡張が予想されるが、検索条件に用いる頻度は低いためJSON型で柔軟に管理する
- **EAVを採用しなかった理由**: 主要なユースケース（連続増収増益の判定、CF符号の比較等）では同一行の複数カラムを同時に参照する必要があり、EAVでは結合が複雑になりSQLiteのパフォーマンスに不利

### financial_metrics を別テーブルにした理由

- CLAUDE.mdの要件: 「マスターテーブルとは別テーブルで管理」
- 生データ（financial_values）と分析指標（financial_metrics）を分離することで、指標の再計算時に生データに影響しない
- `consecutive_revenue_growth` 等のインデックスを活用した高速検索が可能

### daily_quotes テーブルの追加

- バリュエーション指標（PER/PBR/PSR）算出に株価データが必要
- データ取り込みパイプラインTODOでも株価データ取り込みが言及されている
- 当初は `financial_metrics.data_json` で管理する方針だが、将来的に時系列株価分析の要望が出た場合に備え、テーブルを用意しておく

### ユースケースへの対応

#### UC1: 6期連続増収増益の企業一覧

```sql
SELECT c.*, fm.consecutive_revenue_growth, fm.revenue_yoy
FROM financial_metrics fm
JOIN companies c ON c.id = fm.company_id
WHERE fm.scope = 0  -- consolidated
  AND fm.period_type = 0  -- annual
  AND fm.fiscal_year_end = (SELECT MAX(fiscal_year_end) FROM financial_metrics WHERE company_id = fm.company_id AND scope = 0 AND period_type = 0)
  AND fm.consecutive_revenue_growth >= 6
  AND fm.consecutive_profit_growth >= 6
ORDER BY fm.revenue_yoy DESC;
```

#### UC2: 営業CF+/投資CF-で、フリーCFがプラス転換した企業

```sql
SELECT c.*, fm_cur.free_cf, fm_prev.free_cf AS prev_free_cf
FROM financial_metrics fm_cur
JOIN financial_metrics fm_prev ON fm_prev.company_id = fm_cur.company_id
  AND fm_prev.scope = fm_cur.scope
  AND fm_prev.period_type = fm_cur.period_type
  AND fm_prev.fiscal_year_end = (
    SELECT MAX(fiscal_year_end) FROM financial_metrics
    WHERE company_id = fm_cur.company_id AND fiscal_year_end < fm_cur.fiscal_year_end
      AND scope = fm_cur.scope AND period_type = fm_cur.period_type
  )
JOIN companies c ON c.id = fm_cur.company_id
WHERE fm_cur.scope = 0
  AND fm_cur.period_type = 0
  AND fm_cur.operating_cf_positive = 1
  AND fm_cur.investing_cf_negative = 1
  AND fm_cur.free_cf_positive = 1
  AND fm_prev.free_cf_positive = 0;
```

#### UC3: ある企業の業績推移の遡及分析

```sql
SELECT fv.fiscal_year_end, fv.net_sales, fv.operating_income, fv.net_income,
       fm.revenue_yoy, fm.operating_income_yoy, fm.roe, fm.operating_margin,
       fm.consecutive_revenue_growth
FROM financial_values fv
JOIN financial_metrics fm ON fm.financial_value_id = fv.id
WHERE fv.company_id = ?
  AND fv.scope = 0
  AND fv.period_type = 0
ORDER BY fv.fiscal_year_end ASC;
```

---

## EDINET/JQUANTS データマッピング

### 企業マスター（companies テーブルへのマッピング）

| companies カラム | JQUANTS listed/info | EDINET 書類一覧 |
|---|---|---|
| edinet_code | - | edinetCode |
| securities_code | Code (5桁) | secCode (5桁、末尾0なし4桁の場合あり) |
| name | CompanyName | filerName |
| name_english | CompanyNameEnglish | - |
| sector_17_code | Sector17Code | - |
| sector_17_name | Sector17CodeName | - |
| sector_33_code | Sector33Code | - |
| sector_33_name | Sector33CodeName | - |
| market_code | MarketCode | - |
| market_name | MarketCodeName | - |
| scale_category | ScaleCategory | - |

### 決算報告書（financial_reports テーブルへのマッピング）

| financial_reports カラム | EDINET 書類一覧 | JQUANTS fins/statements |
|---|---|---|
| doc_id | docID | - |
| doc_type_code | docTypeCode | TypeOfDocument |
| report_type | docTypeCode から変換 | TypeOfCurrentPeriod から変換 |
| fiscal_year_start | - | CurrentFiscalYearStartDate |
| fiscal_year_end | periodEnd | CurrentFiscalYearEndDate |
| period_start | periodStart | CurrentPeriodStartDate |
| period_end | periodEnd | CurrentPeriodEndDate |
| submitted_at | submitDateTime | - |
| disclosed_at | - | DisclosedDate |
| source | edinet=0 固定 | jquants=1 固定 |

#### report_type 変換ルール

EDINET docTypeCode:
- `120` → annual
- `140` → (periodStart/periodEndの差から q1/q2/q3 を判定)
- `160` → semi_annual

JQUANTS TypeOfCurrentPeriod:
- `FY` → annual
- `1Q` → q1
- `2Q` → q2
- `3Q` → q3

### 財務数値（financial_values テーブルへのマッピング）

| financial_values カラム | JQUANTS fins/statements | EDINET XBRL要素名 |
|---|---|---|
| net_sales | NetSales | jppfs_cor:NetSales |
| operating_income | OperatingProfit | jppfs_cor:OperatingIncome |
| ordinary_income | OrdinaryProfit | jppfs_cor:OrdinaryIncome |
| net_income | Profit | jppfs_cor:ProfitLossAttributableToOwnersOfParent |
| eps | EarningsPerShare | - |
| diluted_eps | DilutedEarningsPerShare | - |
| total_assets | TotalAssets | jppfs_cor:Assets |
| net_assets | Equity | jppfs_cor:NetAssets |
| equity_ratio | EquityToAssetRatio | - |
| bps | BookValuePerShare | - |
| operating_cf | CashFlowsFromOperatingActivities | jppfs_cor:NetCashProvidedByUsedInOperatingActivities |
| investing_cf | CashFlowsFromInvestingActivities | jppfs_cor:NetCashProvidedByUsedInInvestmentActivities |
| financing_cf | CashFlowsFromFinancingActivities | jppfs_cor:NetCashProvidedByUsedInFinancingActivities |
| cash_and_equivalents | CashAndEquivalents | jppfs_cor:CashAndCashEquivalentsAtEndOfPeriod |
| shares_outstanding | NumberOfIssuedAndOutstandingSharesAtTheEndOfFiscalYearIncludingTreasuryStock | - |
| treasury_shares | NumberOfTreasuryStockAtTheEndOfFiscalYear | - |

注意事項:
- JQUANTS fins/statements の値はすべてString型で返却される。数値変換が必要
- IFRS/USGAAP適用企業では ordinary_income (経常利益) がnullとなる
- EDINET XBRL コンテキスト: 連結は `CurrentYearDuration` / `CurrentYearInstant`、個別は `CurrentYearDuration_NonConsolidatedMember`

---

## 実装順序

1. JsonAttribute concern
2. マイグレーション（2-1 〜 2-6 を順に作成）
3. `rails db:migrate` の実行
4. モデルファイル作成
5. テスト作成・実行
