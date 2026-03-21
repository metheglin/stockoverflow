# DEVELOP: 企業インテリジェンスレポート自動生成

## 概要

1社について、タイムライン・セクターポジション・トレンド分類・複合スコア・主要イベントを統合した構造化レポートを自動生成する機能を実装する。プロジェクトの主要ユースケース「ある企業の業績が飛躍し始める直前にどのような決算・財務上の変化があったかを調べる」において、最終的にユーザーが「調べる」行為を支援するための出力レイヤーである。

## 背景

- `dev_company_financial_timeline_view` は時系列の生データ構造を返すが、解釈・要約は含まない
- `dev_screening_result_table_formatter` はスクリーニング結果の表示に特化しており、1社の深堀りレポートとは目的が異なる
- `dev_company_comparison_report` は複数企業の比較であり、1社の包括的レポートではない
- 現状では個別のデータ（FinancialValue, FinancialMetric, DailyQuote等）を手動で組み合わせて企業を「調べる」必要がある
- これらを統合した構造化レポートが、ユーザー体験の最終マイルとして不足している

## 実装内容

### 1. Company::IntelligenceReport クラス

**配置先**: `app/models/company/intelligence_report.rb`

```ruby
class Company::IntelligenceReport
  attr_reader :company, :scope_type, :period_type

  def initialize(company:, scope_type: :consolidated, period_type: :annual)
    @company = company
    @scope_type = scope_type
    @period_type = period_type
  end

  # レポートを生成する
  #
  # @return [Hash] 構造化レポート
  def generate
    {
      company_profile: build_company_profile,
      financial_summary: build_financial_summary,
      growth_analysis: build_growth_analysis,
      profitability_analysis: build_profitability_analysis,
      cash_flow_analysis: build_cash_flow_analysis,
      sector_position: build_sector_position,
      highlights: build_highlights,
      generated_at: Time.current,
    }
  end
end
```

### 2. レポートの構成要素

#### company_profile
- 企業基本情報（名前、証券コード、セクター、市場区分）
- 直近のfinancial_valueから主要数値のサマリー

#### financial_summary
- 直近3-5期の主要財務数値の推移（net_sales, operating_income, net_income, EPS, BPS）
- 各数値の前期比

#### growth_analysis
- 売上・利益のYoY推移
- 連続増収増益期数
- CAGR（3年/5年）（data_json内に存在する場合）
- 成長の加速/減速の判定

#### profitability_analysis
- ROE, ROA, 営業利益率の推移
- トレンド方向（data_json内のtrend classificationがあれば利用）
- 直近値とその推移

#### cash_flow_analysis
- 営業CF / 投資CF / 財務CF / FCFの推移
- CF構造パターンの判定（成長投資型、安定型、縮小型等）

#### sector_position
- SectorMetricが存在する場合、セクター内でのポジション（quartile等）を表示
- 主要指標についてセクター平均との差

#### highlights
- 注目すべきポイントの自動抽出:
  - 連続増収増益がN期以上であれば「N期連続増収増益」
  - FCFがプラス転換していれば「FCFプラス転換」
  - トレンドがturning_upなら「改善転換」
  - セクター上位25%の指標があれば「{指標}がセクター上位」
  - 最新期に大きなYoY変化があれば「{指標}が大幅変化」

### 3. 出力

- Hashで返却し、呼び出し側がフォーマットを選択できるようにする
- 将来的に `dev_screening_result_table_formatter` と同様のフォーマッター連携を想定

## テスト

- `#generate` がHashで必要なキーを全て含むこと
- `#build_highlights` が条件に応じた適切なハイライトを生成すること
- データが不足している（FinancialMetricが存在しない等）場合にエラーにならないこと
- `#build_growth_analysis` が直近N期のYoY推移を正しく構築すること

## 依存関係

- `dev_company_financial_timeline_view` のFinancialTimelineQueryまたは類似のデータ取得ロジックを内部利用
- セクター分析（`dev_sector_analysis_foundation`）の実装があれば sector_position を充実化
- トレンド分類（`dev_metric_trend_classification`）の実装があればhighlightsを強化
- 上記が未実装の場合でも基本レポートは生成可能とする（progressive enhancement）

## 関連TODO

- `dev_company_financial_timeline_view` - データ取得層（本TODOが上位レイヤー）
- `dev_sector_analysis_foundation` - セクターポジション情報の提供元
- `dev_metric_trend_classification` - トレンドラベルの提供元
- `plan_pre_breakthrough_pattern_analysis` - 飛躍前分析の基盤データとして活用
- `dev_rake_operations_tasks` - Rakeタスクからレポート生成を呼び出す導線
