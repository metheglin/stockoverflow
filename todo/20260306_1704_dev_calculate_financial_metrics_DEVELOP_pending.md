# 指標算出ジョブ実装

## 概要

`financial_values` テーブルの財務数値から各種分析指標を算出し、`financial_metrics` テーブルに保存するジョブを実装する。
決算データ取り込みジョブの後に実行されることを想定。

## 前提知識

### 算出する指標一覧

#### 成長性指標（YoY: 前年同期比）

全て小数で表現する（0.15 = 15%成長、-0.10 = 10%減少）。

| 指標 | カラム | 算出式 |
|-----|--------|-------|
| 売上高YoY | `revenue_yoy` | (当期net_sales - 前期net_sales) / \|前期net_sales\| |
| 営業利益YoY | `operating_income_yoy` | (当期operating_income - 前期) / \|前期\| |
| 経常利益YoY | `ordinary_income_yoy` | (当期ordinary_income - 前期) / \|前期\| |
| 純利益YoY | `net_income_yoy` | (当期net_income - 前期) / \|前期\| |
| EPS YoY | `eps_yoy` | (当期eps - 前期eps) / \|前期eps\| |

前期の値が0またはnilの場合、YoYはnilとする。
分母には前期の絶対値を使用（前期が赤字 → 今期黒字転換の場合も正しく計算できる）。

#### 収益性指標

| 指標 | カラム | 算出式 |
|-----|--------|-------|
| ROE | `roe` | net_income / net_assets |
| ROA | `roa` | net_income / total_assets |
| 営業利益率 | `operating_margin` | operating_income / net_sales |
| 経常利益率 | `ordinary_margin` | ordinary_income / net_sales |
| 純利益率 | `net_margin` | net_income / net_sales |

分母が0またはnilの場合、指標はnilとする。

注: ROEの算出にはより厳密には（期首+期末）/2 の平均純資産を使うべきだが、
前期のB/Sデータが取得できていない場合があるため、期末の値で簡易算出する。
将来的に平均値ベースに改善する余地を残す。

#### CF指標

| 指標 | カラム | 算出式 |
|-----|--------|-------|
| フリーCF | `free_cf` | operating_cf + investing_cf |
| 営業CF正 | `operating_cf_positive` | operating_cf > 0 |
| 投資CF負 | `investing_cf_negative` | investing_cf < 0 |
| フリーCF正 | `free_cf_positive` | free_cf > 0 |

operating_cf または investing_cf がnilの場合、CF指標はnilとする。

#### 連続指標

| 指標 | カラム | 算出式 |
|-----|--------|-------|
| 連続増収期数 | `consecutive_revenue_growth` | revenue_yoy > 0 なら前期の値+1、それ以外は0 |
| 連続増益期数 | `consecutive_profit_growth` | net_income_yoy > 0 なら前期の値+1、それ以外は0 |

前期の `financial_metrics` レコードが存在しない場合:
- YoY > 0 であれば 1（連続1期目）
- YoY <= 0 または nil であれば 0

#### バリュエーション指標（data_json格納）

| 指標 | data_json key | 算出式 |
|-----|---------------|-------|
| PER | `per` | 株価 / EPS |
| PBR | `pbr` | 株価 / BPS |
| PSR | `psr` | 時価総額 / net_sales |
| 配当利回り | `dividend_yield` | 年間配当 / 株価 |

株価は `daily_quotes` テーブルから `fiscal_year_end` に最も近い営業日の終値（`adjusted_close`）を使用する。
`daily_quotes` にデータがない場合、バリュエーション指標はnilとする。

時価総額 = 株価 * shares_outstanding

### 前期データの特定

同一 `company_id`, `scope`, `period_type` で `fiscal_year_end` が1年前のレコードを前期とする。
厳密な1年前の日付ではなく、以下のルールで検索:

```ruby
# fiscal_year_end が 2024-03-31 の場合、前期は 2023-03-01 〜 2023-04-30 の範囲で検索
prev_start = fiscal_year_end - 13.months
prev_end = fiscal_year_end - 11.months
FinancialValue.where(company_id:, scope:, period_type:, fiscal_year_end: prev_start..prev_end)
```

これにより、決算期が月末の企業（3/31, 12/31等）と月中の企業の両方に対応できる。

### 実行頻度・運用

- **実行頻度**: 決算データ取り込みジョブの後に実行（日次）
- **対象**: `financial_values` に対応する `financial_metrics` が存在しない、または `financial_values.updated_at` > `financial_metrics.updated_at` のレコード
- **再計算**: 引数で `recalculate: true` を指定した場合、全レコードを再計算

### エラーハンドリング

- 個別企業・個別決算期の算出失敗時はログに記録して次のレコードへ継続

---

## 実装タスク

### タスク1: FinancialMetric モデルへの算出メソッド追加

#### ファイル: `app/models/financial_metric.rb`

```ruby
class FinancialMetric < ApplicationRecord
  include JsonAttribute

  belongs_to :company
  belongs_to :financial_value

  enum :scope, { consolidated: 0, non_consolidated: 1 }
  enum :period_type, { annual: 0, q1: 1, q2: 2, q3: 3 }

  define_json_attributes :data_json, schema: {
    per: { type: :decimal },
    pbr: { type: :decimal },
    psr: { type: :decimal },
    dividend_yield: { type: :decimal },
    ev_ebitda: { type: :decimal },
  }

  # 2つの FinancialValue から成長性指標（YoY）を算出する
  #
  # @param current_fv [FinancialValue] 当期の財務数値
  # @param previous_fv [FinancialValue, nil] 前期の財務数値
  # @return [Hash] YoY指標のHash
  #
  # 例:
  #   yoy = FinancialMetric.get_growth_metrics(current_fv, previous_fv)
  #   # => { revenue_yoy: 0.15, operating_income_yoy: 0.20, ... }
  #
  def self.get_growth_metrics(current_fv, previous_fv)
    return {} unless previous_fv

    {
      revenue_yoy: compute_yoy(current_fv.net_sales, previous_fv.net_sales),
      operating_income_yoy: compute_yoy(current_fv.operating_income, previous_fv.operating_income),
      ordinary_income_yoy: compute_yoy(current_fv.ordinary_income, previous_fv.ordinary_income),
      net_income_yoy: compute_yoy(current_fv.net_income, previous_fv.net_income),
      eps_yoy: compute_yoy(current_fv.eps, previous_fv.eps),
    }
  end

  # FinancialValue から収益性指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] 収益性指標のHash
  def self.get_profitability_metrics(fv)
    {
      roe: safe_divide(fv.net_income, fv.net_assets),
      roa: safe_divide(fv.net_income, fv.total_assets),
      operating_margin: safe_divide(fv.operating_income, fv.net_sales),
      ordinary_margin: safe_divide(fv.ordinary_income, fv.net_sales),
      net_margin: safe_divide(fv.net_income, fv.net_sales),
    }
  end

  # FinancialValue から CF指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @return [Hash] CF指標のHash
  def self.get_cf_metrics(fv)
    result = {}

    if fv.operating_cf.present? && fv.investing_cf.present?
      free_cf = fv.operating_cf + fv.investing_cf
      result[:free_cf] = free_cf
      result[:free_cf_positive] = free_cf > 0
    end

    result[:operating_cf_positive] = fv.operating_cf > 0 if fv.operating_cf.present?
    result[:investing_cf_negative] = fv.investing_cf < 0 if fv.investing_cf.present?

    result
  end

  # 連続増収増益期数を算出する
  #
  # @param growth_metrics [Hash] get_growth_metricsの結果
  # @param previous_metric [FinancialMetric, nil] 前期の指標
  # @return [Hash] 連続指標のHash
  def self.get_consecutive_metrics(growth_metrics, previous_metric)
    prev_revenue = previous_metric&.consecutive_revenue_growth || 0
    prev_profit = previous_metric&.consecutive_profit_growth || 0

    {
      consecutive_revenue_growth:
        growth_metrics[:revenue_yoy].present? && growth_metrics[:revenue_yoy] > 0 ?
          prev_revenue + 1 : 0,
      consecutive_profit_growth:
        growth_metrics[:net_income_yoy].present? && growth_metrics[:net_income_yoy] > 0 ?
          prev_profit + 1 : 0,
    }
  end

  # バリュエーション指標を算出する
  #
  # @param fv [FinancialValue] 財務数値
  # @param stock_price [Numeric, nil] 決算期末の株価
  # @return [Hash] バリュエーション指標のHash（data_json格納用）
  def self.get_valuation_metrics(fv, stock_price)
    return {} unless stock_price

    result = {}
    result["per"] = safe_divide(stock_price, fv.eps)&.to_f if fv.eps.present?
    result["pbr"] = safe_divide(stock_price, fv.bps)&.to_f if fv.bps.present?

    if fv.shares_outstanding.present? && fv.net_sales.present? && fv.net_sales > 0
      market_cap = stock_price * fv.shares_outstanding
      result["psr"] = (market_cap.to_d / fv.net_sales).to_f
    end

    if fv.data_json&.dig("dividend_per_share_annual").present? && stock_price > 0
      dividend = fv.data_json["dividend_per_share_annual"].to_f
      result["dividend_yield"] = (dividend / stock_price).to_f
    end

    result
  end

  # YoY（前年同期比）を算出する
  #
  # @param current [Numeric, nil] 当期の値
  # @param previous [Numeric, nil] 前期の値
  # @return [BigDecimal, nil] YoY比率（小数表現）
  def self.compute_yoy(current, previous)
    return nil if current.nil? || previous.nil? || previous == 0

    ((current.to_d - previous.to_d) / previous.to_d.abs).round(4)
  end

  # 安全な除算（分母が0またはnilの場合はnilを返す）
  #
  # @param numerator [Numeric, nil]
  # @param denominator [Numeric, nil]
  # @return [BigDecimal, nil]
  def self.safe_divide(numerator, denominator)
    return nil if numerator.nil? || denominator.nil? || denominator == 0

    (numerator.to_d / denominator.to_d).round(4)
  end
end
```

### タスク2: CalculateFinancialMetricsJob の実装

#### ファイル: `app/jobs/calculate_financial_metrics_job.rb`

```ruby
class CalculateFinancialMetricsJob < ApplicationJob
  # 指標算出ジョブ
  #
  # @param recalculate [Boolean] trueの場合全レコードを再計算
  # @param company_id [Integer, nil] 特定企業のみ算出する場合に指定
  #
  def perform(recalculate: false, company_id: nil)
    @stats = { calculated: 0, errors: 0 }

    target_values = build_target_scope(recalculate: recalculate, company_id: company_id)

    target_values.find_each do |fv|
      calculate_metrics_for(fv)
    end

    log_result
  end

  private

  # 算出対象の FinancialValue スコープを構築
  def build_target_scope(recalculate:, company_id:)
    scope = FinancialValue.all
    scope = scope.where(company_id: company_id) if company_id

    if recalculate
      scope
    else
      # financial_metrics が存在しない、または financial_values の更新日時が新しいレコード
      scope.left_joins(:financial_metric)
           .where(
             "financial_metrics.id IS NULL OR financial_values.updated_at > financial_metrics.updated_at"
           )
    end
  end

  # 1つの FinancialValue に対して指標を算出
  def calculate_metrics_for(fv)
    # 前期の FinancialValue を検索
    previous_fv = find_previous_financial_value(fv)

    # 前期の FinancialMetric を検索（連続指標の算出に必要）
    previous_metric = previous_fv ? find_metric(previous_fv) : nil

    # 各種指標を算出
    growth = FinancialMetric.get_growth_metrics(fv, previous_fv)
    profitability = FinancialMetric.get_profitability_metrics(fv)
    cf = FinancialMetric.get_cf_metrics(fv)
    consecutive = FinancialMetric.get_consecutive_metrics(growth, previous_metric)
    valuation = FinancialMetric.get_valuation_metrics(fv, load_stock_price(fv))

    # FinancialMetric の作成/更新
    metric = FinancialMetric.find_or_initialize_by(
      company_id: fv.company_id,
      fiscal_year_end: fv.fiscal_year_end,
      scope: fv.scope,
      period_type: fv.period_type,
    )

    metric.assign_attributes(
      financial_value: fv,
      **growth,
      **profitability,
      **cf,
      **consecutive,
    )

    # バリュエーション指標は data_json にマージ
    if valuation.any?
      metric.data_json = (metric.data_json || {}).merge(valuation)
    end

    metric.save! if metric.new_record? || metric.changed?
    @stats[:calculated] += 1
  rescue => e
    @stats[:errors] += 1
    Rails.logger.error(
      "[CalculateFinancialMetricsJob] Failed for FV##{fv.id} " \
      "(company=#{fv.company_id}, fy=#{fv.fiscal_year_end}): #{e.message}"
    )
  end

  # 前期の FinancialValue を検索
  # fiscal_year_end の約1年前（±1ヶ月）の範囲で検索
  def find_previous_financial_value(fv)
    prev_start = fv.fiscal_year_end - 13.months
    prev_end = fv.fiscal_year_end - 11.months

    FinancialValue
      .where(
        company_id: fv.company_id,
        scope: fv.scope,
        period_type: fv.period_type,
        fiscal_year_end: prev_start..prev_end,
      )
      .order(fiscal_year_end: :desc)
      .first
  end

  # FinancialValue に対応する FinancialMetric を検索
  def find_metric(fv)
    FinancialMetric.find_by(
      company_id: fv.company_id,
      fiscal_year_end: fv.fiscal_year_end,
      scope: fv.scope,
      period_type: fv.period_type,
    )
  end

  # 決算期末日に最も近い株価（終値）を取得
  # fiscal_year_end の前後5営業日の範囲で検索し、最も近い日の調整後終値を返す
  def load_stock_price(fv)
    DailyQuote
      .where(company_id: fv.company_id)
      .where(traded_on: (fv.fiscal_year_end - 7.days)...(fv.fiscal_year_end + 7.days))
      .order(Arel.sql("ABS(JULIANDAY(traded_on) - JULIANDAY('#{fv.fiscal_year_end}'))"))
      .pick(:adjusted_close)
  end

  def log_result
    Rails.logger.info(
      "[CalculateFinancialMetricsJob] Completed: " \
      "#{@stats[:calculated]} calculated, #{@stats[:errors]} errors"
    )
  end
end
```

### タスク3: テスト

#### ファイル: `spec/models/financial_metric_spec.rb`

```ruby
RSpec.describe FinancialMetric do
  describe ".compute_yoy" do
    it "正の成長率を算出する" do
      expect(FinancialMetric.compute_yoy(115, 100)).to eq(BigDecimal("0.15"))
    end

    it "負の成長率を算出する" do
      expect(FinancialMetric.compute_yoy(85, 100)).to eq(BigDecimal("-0.15"))
    end

    it "前期が赤字→今期黒字の場合も正しく算出する" do
      # 前期 -100 → 今期 50: 変化量150、|前期|100 → 1.5 (150%)
      expect(FinancialMetric.compute_yoy(50, -100)).to eq(BigDecimal("1.5"))
    end

    it "前期が0の場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(100, 0)).to be_nil
    end

    it "当期がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(nil, 100)).to be_nil
    end

    it "前期がnilの場合はnilを返す" do
      expect(FinancialMetric.compute_yoy(100, nil)).to be_nil
    end
  end

  describe ".safe_divide" do
    it "正常な除算を実行する" do
      expect(FinancialMetric.safe_divide(100, 1000)).to eq(BigDecimal("0.1"))
    end

    it "分母が0の場合はnilを返す" do
      expect(FinancialMetric.safe_divide(100, 0)).to be_nil
    end

    it "分子がnilの場合はnilを返す" do
      expect(FinancialMetric.safe_divide(nil, 100)).to be_nil
    end

    it "分母がnilの場合はnilを返す" do
      expect(FinancialMetric.safe_divide(100, nil)).to be_nil
    end
  end

  describe ".get_growth_metrics" do
    it "全YoY指標を算出する" do
      current_fv = FinancialValue.new(
        net_sales: 1150, operating_income: 240, ordinary_income: 260,
        net_income: 180, eps: BigDecimal("66.76")
      )
      previous_fv = FinancialValue.new(
        net_sales: 1000, operating_income: 200, ordinary_income: 220,
        net_income: 150, eps: BigDecimal("55.50")
      )

      result = FinancialMetric.get_growth_metrics(current_fv, previous_fv)

      expect(result[:revenue_yoy]).to eq(BigDecimal("0.15"))
      expect(result[:operating_income_yoy]).to eq(BigDecimal("0.2"))
      expect(result[:net_income_yoy]).to eq(BigDecimal("0.2"))
      expect(result[:eps_yoy]).to be_a(BigDecimal)
    end

    it "前期がnilの場合は空Hashを返す" do
      current_fv = FinancialValue.new(net_sales: 1150)
      result = FinancialMetric.get_growth_metrics(current_fv, nil)

      expect(result).to eq({})
    end
  end

  describe ".get_profitability_metrics" do
    it "収益性指標を算出する" do
      fv = FinancialValue.new(
        net_sales: 10000, operating_income: 1500, ordinary_income: 1600,
        net_income: 1000, total_assets: 50000, net_assets: 20000,
      )

      result = FinancialMetric.get_profitability_metrics(fv)

      expect(result[:operating_margin]).to eq(BigDecimal("0.15"))
      expect(result[:ordinary_margin]).to eq(BigDecimal("0.16"))
      expect(result[:net_margin]).to eq(BigDecimal("0.1"))
      expect(result[:roe]).to eq(BigDecimal("0.05"))
      expect(result[:roa]).to eq(BigDecimal("0.02"))
    end

    it "net_salesが0の場合マージン系はnilになる" do
      fv = FinancialValue.new(net_sales: 0, operating_income: 100, net_income: 50,
                              total_assets: 1000, net_assets: 500)

      result = FinancialMetric.get_profitability_metrics(fv)

      expect(result[:operating_margin]).to be_nil
      expect(result[:net_margin]).to be_nil
    end
  end

  describe ".get_cf_metrics" do
    it "CF指標を算出する" do
      fv = FinancialValue.new(operating_cf: 5000, investing_cf: -2000)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to eq(3000)
      expect(result[:operating_cf_positive]).to eq(true)
      expect(result[:investing_cf_negative]).to eq(true)
      expect(result[:free_cf_positive]).to eq(true)
    end

    it "フリーCFが負の場合" do
      fv = FinancialValue.new(operating_cf: 2000, investing_cf: -5000)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to eq(-3000)
      expect(result[:free_cf_positive]).to eq(false)
    end

    it "CF値がnilの場合" do
      fv = FinancialValue.new(operating_cf: nil, investing_cf: nil)
      result = FinancialMetric.get_cf_metrics(fv)

      expect(result[:free_cf]).to be_nil
      expect(result[:operating_cf_positive]).to be_nil
    end
  end

  describe ".get_consecutive_metrics" do
    it "増収増益の場合は前期+1" do
      growth = { revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.2") }
      prev_metric = FinancialMetric.new(
        consecutive_revenue_growth: 3,
        consecutive_profit_growth: 2,
      )

      result = FinancialMetric.get_consecutive_metrics(growth, prev_metric)

      expect(result[:consecutive_revenue_growth]).to eq(4)
      expect(result[:consecutive_profit_growth]).to eq(3)
    end

    it "減収の場合は0にリセット" do
      growth = { revenue_yoy: BigDecimal("-0.05"), net_income_yoy: BigDecimal("0.1") }
      prev_metric = FinancialMetric.new(
        consecutive_revenue_growth: 5,
        consecutive_profit_growth: 3,
      )

      result = FinancialMetric.get_consecutive_metrics(growth, prev_metric)

      expect(result[:consecutive_revenue_growth]).to eq(0)
      expect(result[:consecutive_profit_growth]).to eq(4)
    end

    it "前期metricがnilの場合は初期値" do
      growth = { revenue_yoy: BigDecimal("0.1"), net_income_yoy: BigDecimal("0.2") }
      result = FinancialMetric.get_consecutive_metrics(growth, nil)

      expect(result[:consecutive_revenue_growth]).to eq(1)
      expect(result[:consecutive_profit_growth]).to eq(1)
    end

    it "YoYがnilの場合は0" do
      growth = { revenue_yoy: nil, net_income_yoy: nil }
      result = FinancialMetric.get_consecutive_metrics(growth, nil)

      expect(result[:consecutive_revenue_growth]).to eq(0)
      expect(result[:consecutive_profit_growth]).to eq(0)
    end
  end

  describe ".get_valuation_metrics" do
    it "バリュエーション指標を算出する" do
      fv = FinancialValue.new(
        eps: BigDecimal("66.76"),
        bps: BigDecimal("380.50"),
        net_sales: 100_000_000_000,
        shares_outstanding: 524_000_000,
      )
      # data_json を手動設定
      allow(fv).to receive(:data_json).and_return({ "dividend_per_share_annual" => 50.0 })

      result = FinancialMetric.get_valuation_metrics(fv, 2000.0)

      expect(result["per"]).to be_within(0.1).of(30.0)
      expect(result["pbr"]).to be_within(0.01).of(5.26)
      expect(result["psr"]).to be_a(Float)
      expect(result["dividend_yield"]).to eq(0.025)
    end

    it "株価がnilの場合は空Hashを返す" do
      fv = FinancialValue.new(eps: BigDecimal("66.76"))
      result = FinancialMetric.get_valuation_metrics(fv, nil)

      expect(result).to eq({})
    end
  end
end
```

---

## 設計判断

### 指標算出ロジックのモデル配置

指標の算出ロジック（`compute_yoy`, `safe_divide`, `get_growth_metrics` 等）は `FinancialMetric` モデルのクラスメソッドとして配置する。理由:
- コーディング規約「テストしやすいことを重視」に準拠。モデルメソッドとして直接テスト可能
- DBアクセスを伴わない純粋な計算ロジックであり、FinancialValue のインスタンスを引数に取る
- ジョブはオーケストレーション（対象レコードの特定・前期データ検索・保存）に専念

### 前期データの検索範囲

`fiscal_year_end ± 1ヶ月` の範囲で前期を検索する理由:
- 多くの企業は3月決算（fiscal_year_end = 3/31）だが、12月決算、6月決算等もある
- 決算期変更の場合、正確に12ヶ月前にならないケースがある
- 2ヶ月幅（-13ヶ月 〜 -11ヶ月）であれば、通常の決算サイクルをカバーできる

### 株価の検索範囲

決算期末日の前後7日間で最も近い営業日の株価を使用する理由:
- 期末日が土日・祝日の場合、当日の株価が存在しない
- 7日間であれば前後の営業日をほぼ確実にカバーできる
- SQLiteの `JULIANDAY` 関数で日付差の絶対値を計算し、最も近い日を選択

### ROEの簡易算出

厳密なROEは（期首純資産 + 期末純資産）/ 2 を分母とするが、前期B/Sデータが常に取得できるとは限らないため、期末純資産のみで簡易算出する。
これは初期実装として妥当であり、データが蓄積された後に平均値ベースに改善する余地を残す。

---

## 実装順序

1. `app/models/financial_metric.rb` にクラスメソッドを追加
2. `app/jobs/calculate_financial_metrics_job.rb` を新規作成
3. `spec/models/financial_metric_spec.rb` を新規作成・テスト実行

---

## ユースケース対応の確認

### UC1: 6期連続増収増益の企業を一覧し、増収率が高い順に並べる

```ruby
# 最新期のfinancial_metricsで、連続増収増益が6以上
FinancialMetric
  .where(scope: :consolidated, period_type: :annual)
  .where("consecutive_revenue_growth >= ?", 6)
  .where("consecutive_profit_growth >= ?", 6)
  .joins(:company)
  .order(revenue_yoy: :desc)
```

### UC2: 営業CF+/投資CF-で、フリーCFがプラスに転換した企業

```ruby
# 当期: 営業CF+, 投資CF-, フリーCF+ の企業のうち
# 前期: フリーCF- だった企業
current_metrics = FinancialMetric
  .where(scope: :consolidated, period_type: :annual,
         operating_cf_positive: true, investing_cf_negative: true, free_cf_positive: true)

current_metrics.select do |m|
  prev = FinancialMetric.find_by(
    company_id: m.company_id, scope: m.scope, period_type: m.period_type,
    fiscal_year_end: (m.fiscal_year_end - 13.months)..(m.fiscal_year_end - 11.months)
  )
  prev && prev.free_cf_positive == false
end
```

### UC3: ある企業の業績推移の遡及分析

```ruby
company = Company.find_by(securities_code: "72030")
FinancialMetric
  .where(company: company, scope: :consolidated, period_type: :annual)
  .includes(:financial_value)
  .order(fiscal_year_end: :asc)
```
