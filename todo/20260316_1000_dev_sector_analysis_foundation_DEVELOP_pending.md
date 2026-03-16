# DEVELOP: セクター・業種別分析基盤 実装

## 概要

33業種別 / 17業種別に統計量（平均・中央値・四分位）を算出・保存し、個別企業のセクター内ポジションを把握できる仕組みを構築する。業種別の統計量はスナップショットとして履歴保持し、セクターのトレンド推移を追えるようにする。

---

## 1. DB マイグレーション: `sector_metrics` テーブル

### 1-1. テーブル設計

```ruby
# db/migrate/XXXXXXXXXX_create_sector_metrics.rb
class CreateSectorMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :sector_metrics do |t|
      t.integer :classification, null: false    # enum: sector_17(0), sector_33(1)
      t.string :sector_code, null: false
      t.string :sector_name, null: false
      t.date :calculated_on, null: false        # 集計基準日（スナップショット日付）
      t.integer :company_count, default: 0, null: false
      t.json :data_json                         # 各指標の統計量

      t.timestamps
    end

    add_index :sector_metrics,
              [:classification, :sector_code, :calculated_on],
              unique: true,
              name: "idx_sector_metrics_unique"
    add_index :sector_metrics,
              [:classification, :calculated_on],
              name: "idx_sector_metrics_classification_date"
  end
end
```

### 1-2. 設計判断

- **専用テーブル採用**: 33業種 + 17業種 = 最大50分類、各分類に11指標の統計量（mean/median/q1/q3/min/max/stddev/count）を格納する必要があり、ApplicationPropertyのkind拡張やEAVでは構造的に不適切
- **JSON型 `data_json`**: 統計量はセクターコードをキーとした参照（lookup）用途であり、統計量の値自体で検索することは想定しない。JSON格納がCLAUDE.md規約に合致
- **`calculated_on` によるスナップショット**: プロジェクト目的「あらゆる指標の推移やトレンドの転換がわかるようにしたい」に対応。ジョブ実行ごとに `Date.current` で記録し、時系列でセクター統計の推移を追跡可能

### 1-3. `data_json` の構造

指標ごとに統計量のHashを格納する。

```json
{
  "roe": {
    "mean": 0.0832,
    "median": 0.0714,
    "q1": 0.0412,
    "q3": 0.1203,
    "min": -0.5012,
    "max": 0.6234,
    "stddev": 0.0823,
    "count": 148
  },
  "roa": { ... },
  "operating_margin": { ... },
  "net_margin": { ... },
  "revenue_yoy": { ... },
  "net_income_yoy": { ... },
  "per": { ... },
  "pbr": { ... },
  "psr": { ... },
  "ev_ebitda": { ... },
  "dividend_yield": { ... }
}
```

---

## 2. SectorMetric モデル

**配置先**: `app/models/sector_metric.rb`

```ruby
class SectorMetric < ApplicationRecord
  # 集計対象の指標キー
  #
  # 固定カラム指標: FinancialMetric の固定カラムから読み取り
  # data_json指標: FinancialMetric の data_json から読み取り
  FIXED_COLUMN_METRICS = %i[
    roe roa operating_margin net_margin
    revenue_yoy net_income_yoy
  ].freeze

  DATA_JSON_METRICS = %i[
    per pbr psr ev_ebitda dividend_yield
  ].freeze

  METRIC_KEYS = (FIXED_COLUMN_METRICS + DATA_JSON_METRICS).freeze

  # 金融セクター（33業種分類）
  # 銀行業・証券商品先物取引業・保険業・その他金融業は
  # ROE/ROA等の比較において一般事業会社と財務構造が大きく異なる
  # 実際のsector_33_codeはJQUANTSデータから確認し設定すること
  FINANCIAL_SECTOR_33_CODES = %w[7050 7100 7150 7200].freeze

  enum :classification, {
    sector_17: 0,
    sector_33: 1,
  }

  # 配列から統計量を算出する
  #
  # @param values [Array<Numeric>] 指標値の配列（nil含む可能性あり）
  # @return [Hash, nil] 統計量Hash。有効値が0件の場合nil
  #
  # 例:
  #   SectorMetric.get_statistics([0.05, 0.08, 0.12, 0.03, 0.15])
  #   # => { "mean" => 0.086, "median" => 0.08, "q1" => 0.05, "q3" => 0.12,
  #   #      "min" => 0.03, "max" => 0.15, "stddev" => 0.0441, "count" => 5 }
  #
  def self.get_statistics(values)
    compacted = values.compact.map(&:to_f)
    return nil if compacted.empty?

    sorted = compacted.sort
    count = sorted.length
    mean = sorted.sum / count

    {
      "mean" => mean.round(4),
      "median" => get_percentile_value(sorted, 50),
      "q1" => get_percentile_value(sorted, 25),
      "q3" => get_percentile_value(sorted, 75),
      "min" => sorted.first.round(4),
      "max" => sorted.last.round(4),
      "stddev" => get_stddev(sorted, mean),
      "count" => count,
    }
  end

  # ソート済み配列からパーセンタイル値を算出する（線形補間法）
  #
  # @param sorted [Array<Float>] 昇順ソート済み配列
  # @param percentile [Numeric] パーセンタイル（0〜100）
  # @return [Float]
  def self.get_percentile_value(sorted, percentile)
    return sorted.first.round(4) if sorted.length == 1

    rank = (percentile / 100.0) * (sorted.length - 1)
    lower = sorted[rank.floor]
    upper = sorted[rank.ceil]

    (lower + (upper - lower) * (rank - rank.floor)).round(4)
  end

  # 標準偏差を算出する
  #
  # @param sorted [Array<Float>] 値の配列
  # @param mean [Float] 平均値
  # @return [Float]
  def self.get_stddev(sorted, mean)
    return 0.0 if sorted.length <= 1

    variance = sorted.sum { |v| (v - mean) ** 2 } / sorted.length
    Math.sqrt(variance).round(4)
  end

  # FinancialMetric から指標値を読み取る
  #
  # 固定カラム指標は直接アクセス、data_json指標はJsonAttributeゲッター経由で取得
  #
  # @param metric [FinancialMetric]
  # @param metric_key [Symbol] METRIC_KEYS のいずれか
  # @return [Numeric, nil]
  def self.get_metric_value(metric, metric_key)
    metric.public_send(metric_key)
  rescue NoMethodError
    nil
  end

  # 特定指標について、セクターの統計量に対する値の相対位置を判定する
  #
  # @param value [Numeric, nil] 個別企業の指標値
  # @param sector_stats [Hash] get_statistics の返却値
  # @return [Hash, nil] { percentile_approx:, vs_mean:, vs_median:, quartile: }
  #
  # 例:
  #   stats = { "mean" => 0.08, "median" => 0.07, "q1" => 0.04, "q3" => 0.12, ... }
  #   SectorMetric.get_relative_position(0.15, stats)
  #   # => { percentile_approx: 87.5, vs_mean: 0.07, vs_median: 0.08, quartile: 4 }
  #
  def self.get_relative_position(value, sector_stats)
    return nil if value.nil? || sector_stats.nil?

    q1 = sector_stats["q1"]
    median = sector_stats["median"]
    q3 = sector_stats["q3"]
    mean = sector_stats["mean"]

    quartile = if value <= q1
                 1
               elsif value <= median
                 2
               elsif value <= q3
                 3
               else
                 4
               end

    {
      vs_mean: (value - mean).round(4),
      vs_median: (value - median).round(4),
      quartile: quartile,
    }
  end

  # 金融セクターかどうかを判定する
  #
  # @param sector_33_code [String]
  # @return [Boolean]
  def self.financial_sector?(sector_33_code)
    FINANCIAL_SECTOR_33_CODES.include?(sector_33_code.to_s)
  end

  # 最新のスナップショット日を取得する
  #
  # @param classification [Symbol] :sector_17 or :sector_33
  # @return [Date, nil]
  def self.load_latest_calculated_on(classification)
    where(classification: classification).maximum(:calculated_on)
  end

  # 最新スナップショットのセクター統計をsector_codeをキーとしたHashで返す
  #
  # @param classification [Symbol] :sector_17 or :sector_33
  # @param calculated_on [Date, nil] nil の場合は最新日
  # @return [Hash<String, SectorMetric>] { sector_code => SectorMetric }
  def self.load_latest_map(classification, calculated_on: nil)
    date = calculated_on || load_latest_calculated_on(classification)
    return {} unless date

    where(classification: classification, calculated_on: date)
      .index_by(&:sector_code)
  end
end
```

---

## 3. CalculateSectorMetricsJob

**配置先**: `app/jobs/calculate_sector_metrics_job.rb`

**実行タイミング**: `CalculateFinancialMetricsJob` の後続として実行。日次〜週次（指標は通期決算ベースのため頻繁な更新は不要。週次推奨）

```ruby
class CalculateSectorMetricsJob < ApplicationJob
  # セクター別統計量を算出し sector_metrics に保存する
  #
  # @param classification [String] "sector_17" or "sector_33"。未指定の場合は両方
  # @param calculated_on [Date] スナップショット日付。デフォルトは当日
  #
  def perform(classification: nil, calculated_on: Date.current)
    @calculated_on = calculated_on
    @stats = { created: 0, updated: 0, errors: 0 }

    # 最新の連結・通期 FinancialMetric を企業ごとに1件ずつ取得
    @latest_metrics = load_latest_metrics

    if classification.nil? || classification == "sector_33"
      calculate_for_classification(:sector_33)
    end
    if classification.nil? || classification == "sector_17"
      calculate_for_classification(:sector_17)
    end

    log_result
  end

  private

  # 全上場企業の最新 連結・通期 FinancialMetric を取得
  #
  # includes(:company) で company の sector 情報を参照可能にする
  def load_latest_metrics
    FinancialMetric
      .consolidated
      .annual
      .where(
        "fiscal_year_end = (SELECT MAX(fm2.fiscal_year_end) FROM financial_metrics fm2 " \
        "WHERE fm2.company_id = financial_metrics.company_id " \
        "AND fm2.scope = financial_metrics.scope " \
        "AND fm2.period_type = financial_metrics.period_type)"
      )
      .includes(:company)
      .where(company_id: Company.listed.select(:id))
      .to_a
  end

  # 指定分類でセクター統計を算出・保存
  def calculate_for_classification(classification)
    sector_attr = classification == :sector_33 ? :sector_33_code : :sector_17_code
    name_attr = classification == :sector_33 ? :sector_33_name : :sector_17_name

    grouped = @latest_metrics.group_by { |m| m.company.public_send(sector_attr) }

    grouped.each do |sector_code, metrics|
      next if sector_code.blank?

      sector_name = metrics.first.company.public_send(name_attr) || sector_code
      calculate_sector(classification, sector_code, sector_name, metrics)
    end
  end

  # 1セクター分の統計を算出・保存
  def calculate_sector(classification, sector_code, sector_name, metrics)
    data_json = {}

    SectorMetric::METRIC_KEYS.each do |metric_key|
      values = metrics.map { |m| SectorMetric.get_metric_value(m, metric_key) }
      stats = SectorMetric.get_statistics(values)
      data_json[metric_key.to_s] = stats if stats
    end

    record = SectorMetric.find_or_initialize_by(
      classification: classification,
      sector_code: sector_code,
      calculated_on: @calculated_on,
    )

    is_new = record.new_record?
    record.assign_attributes(
      sector_name: sector_name,
      company_count: metrics.length,
      data_json: data_json,
    )

    record.save! if record.new_record? || record.changed?
    @stats[is_new ? :created : :updated] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[CalculateSectorMetricsJob] Failed for #{classification}/#{sector_code}: #{e.message}"
    )
  end

  def log_result
    Rails.logger.info(
      "[CalculateSectorMetricsJob] Completed: " \
      "#{@stats[:created]} created, #{@stats[:updated]} updated, #{@stats[:errors]} errors"
    )
  end
end
```

### 3-1. 算出フロー

1. `Company.listed` に紐づく最新の連結・通期 `FinancialMetric` を一括取得（`latest_period` 相当のサブクエリ）
2. `includes(:company)` で企業の `sector_33_code` / `sector_17_code` を参照可能にする
3. セクターコードでグループ化
4. 各セクターについて、11指標の統計量（mean/median/q1/q3/min/max/stddev/count）を算出
5. `sector_metrics` に upsert（`find_or_initialize_by` + `save!`）

### 3-2. パフォーマンス見積もり

- 上場企業数: 約4,000社
- 33業種分類: 約33セクター
- 17業種分類: 約17セクター
- 1回の実行で作成されるレコード: 約50件
- メモリ: 4,000件の FinancialMetric + Company を一括ロード（数十MB程度）
- 所要時間: 数秒〜数十秒

---

## 4. Company::SectorComparisonQuery

**配置先**: `app/models/company/sector_comparison_query.rb`

**目的**: セクター統計量と個別企業の指標を比較し、「業種平均より高い/低い」等の条件でスクリーニングする。

```ruby
class Company::SectorComparisonQuery
  VALID_CONDITIONS = %i[above_average above_median top_quartile bottom_quartile].freeze

  attr_reader :metric, :condition, :classification, :scope_type, :period_type,
              :exclude_financial_sectors, :limit

  # @param metric [Symbol] 比較する指標（SectorMetric::METRIC_KEYS のいずれか）
  # @param condition [Symbol] 比較条件
  #   :above_average    - セクター平均を上回る企業
  #   :above_median     - セクター中央値を上回る企業
  #   :top_quartile     - セクター内Q3を上回る企業（上位25%）
  #   :bottom_quartile  - セクター内Q1を下回る企業（下位25%）
  # @param classification [Symbol] :sector_17 or :sector_33（デフォルト: :sector_33）
  # @param scope_type [Symbol] :consolidated or :non_consolidated（デフォルト: :consolidated）
  # @param period_type [Symbol] :annual（デフォルト: :annual）
  # @param exclude_financial_sectors [Boolean] 金融セクターを除外するか（デフォルト: false）
  # @param limit [Integer, nil] 取得件数上限
  def initialize(metric:, condition: :above_average, classification: :sector_33,
                 scope_type: :consolidated, period_type: :annual,
                 exclude_financial_sectors: false, limit: nil)
    @metric = metric
    @condition = condition
    @classification = classification
    @scope_type = scope_type
    @period_type = period_type
    @exclude_financial_sectors = exclude_financial_sectors
    @limit = limit
  end

  # クエリを実行し、条件を満たす企業のリストを返す
  #
  # @return [Array<Hash>]
  #
  # 返却例:
  #   [
  #     {
  #       company: #<Company>,
  #       metric: #<FinancialMetric>,
  #       value: 0.15,
  #       sector_code: "3050",
  #       sector_name: "情報・通信業",
  #       sector_stats: { "mean" => 0.08, "median" => 0.07, ... },
  #       relative_position: { vs_mean: 0.07, vs_median: 0.08, quartile: 4 },
  #     },
  #     ...
  #   ]
  #
  def execute
    sector_map = load_sector_map
    latest_metrics = load_latest_metrics
    threshold_map = build_threshold_map(sector_map)

    results = []

    latest_metrics.each do |fm|
      sector_code = get_sector_code(fm)
      next if sector_code.blank?
      next if @exclude_financial_sectors && SectorMetric.financial_sector?(sector_code)

      threshold = threshold_map[sector_code]
      next unless threshold

      value = SectorMetric.get_metric_value(fm, @metric)
      next if value.nil?
      next unless meets_condition?(value, threshold)

      sector_metric = sector_map[sector_code]
      sector_stats = sector_metric&.data_json&.dig(@metric.to_s)

      results << {
        company: fm.company,
        metric: fm,
        value: value.to_f,
        sector_code: sector_code,
        sector_name: sector_metric&.sector_name,
        sector_stats: sector_stats,
        relative_position: SectorMetric.get_relative_position(value.to_f, sector_stats),
      }
    end

    results = results.sort_by { |r| -(r[:value] || 0) }
    results = results.first(@limit) if @limit
    results
  end

  # セクターごとの閾値マップを構築する
  #
  # @param sector_map [Hash<String, SectorMetric>]
  # @return [Hash<String, Float>] { sector_code => threshold_value }
  def build_threshold_map(sector_map)
    stat_key = case @condition
               when :above_average then "mean"
               when :above_median then "median"
               when :top_quartile then "q3"
               when :bottom_quartile then "q1"
               else "mean"
               end

    sector_map.each_with_object({}) do |(code, sm), map|
      stats = sm.data_json&.dig(@metric.to_s)
      next unless stats

      map[code] = stats[stat_key]
    end
  end

  private

  def load_sector_map
    SectorMetric.load_latest_map(@classification)
  end

  def load_latest_metrics
    FinancialMetric
      .where(scope: @scope_type, period_type: @period_type)
      .where(
        "fiscal_year_end = (SELECT MAX(fm2.fiscal_year_end) FROM financial_metrics fm2 " \
        "WHERE fm2.company_id = financial_metrics.company_id " \
        "AND fm2.scope = financial_metrics.scope " \
        "AND fm2.period_type = financial_metrics.period_type)"
      )
      .includes(:company)
      .where(company_id: Company.listed.select(:id))
  end

  def get_sector_code(fm)
    if @classification == :sector_33
      fm.company.sector_33_code
    else
      fm.company.sector_17_code
    end
  end

  def meets_condition?(value, threshold)
    case @condition
    when :above_average, :above_median, :top_quartile
      value > threshold
    when :bottom_quartile
      value < threshold
    end
  end
end
```

### 4-1. 使用例

```ruby
# 業種平均より ROE が高い企業（33業種分類）
query = Company::SectorComparisonQuery.new(
  metric: :roe,
  condition: :above_average,
  classification: :sector_33,
)
results = query.execute

# 業種内 PBR 上位25% の企業（金融セクター除外）
query = Company::SectorComparisonQuery.new(
  metric: :pbr,
  condition: :top_quartile,
  exclude_financial_sectors: true,
  limit: 50,
)
results = query.execute
```

### 4-2. 設計判断

- **二段階方式**: セクター統計をまずロードし、Rubyレベルで個別企業と比較する方式を採用。SQL JOINでセクター比較をおこなうことも可能だが、data_json内の統計値とdata_json内の指標値のJSON経由のSQL比較はSQLiteとの互換性が低く、テスタビリティも落ちる
- **パフォーマンス**: 上場企業は約4,000件。メモリ上で全件走査しても十分高速（ミリ秒オーダー）
- **金融セクター除外オプション**: 銀行業・保険業・証券業等は一般事業会社とROE/ROA等の水準が構造的に異なるため、クロスセクター分析時に除外するオプションを提供。ただしセクター内比較では問題ないため、デフォルトはfalse
- **`build_threshold_map` を公開メソッドに**: テスタビリティのために公開。閾値マップの構築ロジックを独立してテスト可能

---

## 5. 金融セクターの取り扱い

### 5-1. 方針

- セクター統計量は金融セクターを含め全セクターについて算出する
- セクター内比較（同じセクター内での企業の相対的位置づけ）は常に有効
- クロスセクター比較や全体スクリーニングにおいて、金融セクターを除外するオプションを提供する
- `SectorMetric::FINANCIAL_SECTOR_33_CODES` で金融セクターを定義。実際のセクターコードはJQUANTSデータから確認し、初回ジョブ実行後に正確な値に更新すること

### 5-2. 金融セクターで注意すべき指標

| 指標 | 注意点 |
|------|--------|
| ROE | 銀行業は高レバレッジのため見かけ上高くなる |
| ROA | 銀行業の総資産は預金を含むため極端に低い |
| 営業利益率 | 銀行業は経常収益ベースのため一般事業会社と比較不可 |
| PBR | 銀行業は1倍以下が一般的で低いわけではない |

---

## 6. テスト計画

### 6-1. SectorMetric モデルテスト

**ファイル**: `spec/models/sector_metric_spec.rb`（新規作成）

#### `.get_statistics`

- 正常な値の配列から統計量が正しく算出されること
- nil を含む配列から nil が除外されて算出されること
- 空の配列で nil が返ること
- 1要素の配列で mean = median = q1 = q3 = min = max であること
- 全要素が同じ値の場合 stddev が 0.0 であること

#### `.get_percentile_value`

- ソート済み配列の中央値（50パーセンタイル）が正しいこと
- 偶数個の配列の中央値が線形補間されること
- 25パーセンタイル（Q1）が正しいこと
- 75パーセンタイル（Q3）が正しいこと
- 1要素の配列でその値が返ること

#### `.get_stddev`

- 正常な値の標準偏差が正しいこと
- 1要素の配列で 0.0 が返ること

#### `.get_metric_value`

- 固定カラム指標（roe等）が正しく読み取れること
- data_json指標（per等）が正しく読み取れること
- 存在しないメソッドで nil が返ること

#### `.get_relative_position`

- セクター平均を上回る値の relative_position が正しいこと
- Q1以下の値で quartile: 1 が返ること
- Q3超の値で quartile: 4 が返ること
- value が nil の場合 nil が返ること

### 6-2. Company::SectorComparisonQuery テスト

**ファイル**: `spec/models/company/sector_comparison_query_spec.rb`（新規作成）

#### `#build_threshold_map`

- sector_map から指定condition（above_average）に応じた閾値が構築されること
- above_median で median 値が閾値となること
- top_quartile で q3 値が閾値となること
- 指標の統計がないセクターがスキップされること

---

## 7. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `db/migrate/XXXXXXXX_create_sector_metrics.rb` | sector_metricsテーブル作成 |
| `app/models/sector_metric.rb` | セクター統計モデル（統計算出メソッド） |
| `app/jobs/calculate_sector_metrics_job.rb` | セクター統計算出ジョブ |
| `app/models/company/sector_comparison_query.rb` | セクター相対スクリーニングQueryObject |
| `spec/models/sector_metric_spec.rb` | SectorMetric テスト |
| `spec/models/company/sector_comparison_query_spec.rb` | SectorComparisonQuery テスト |

### 既存変更

なし（既存モデル・ジョブへの変更は不要）

---

## 8. 実装順序

1. マイグレーション作成・実行（`create_sector_metrics`）
2. `SectorMetric` モデル実装（統計算出クラスメソッド群）
3. `SectorMetric` テスト実装・実行
4. `CalculateSectorMetricsJob` 実装
5. `Company::SectorComparisonQuery` 実装
6. `Company::SectorComparisonQuery` テスト実装・実行
7. 全テスト実行・確認

---

## 9. 将来の拡張

- **四半期集計**: 現在は通期（annual）のみ対象。四半期データが十分蓄積された段階で `period_type` を考慮した集計を追加可能
- **セクター統計のトレンド**: `calculated_on` の時系列データを用いて「セクター平均ROEが上昇トレンドか」を分析するQueryObjectの追加
- **既存ScreeningQueryとの統合**: `Company::ScreeningQuery` の filters に `sector_relative` 条件を追加し、セクター比較を汎用スクリーニングに組み込む
- **Web API**: セクター統計エンドポイント（`GET /api/v1/sectors/:code/metrics`）の追加
- **FINANCIAL_SECTOR_33_CODES の検証**: 初回ジョブ実行後に実データからセクターコードを確認し、定数を正確な値に更新する
