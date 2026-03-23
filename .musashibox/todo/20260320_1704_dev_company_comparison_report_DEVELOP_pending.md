# 複数企業の横並び比較レポート機能

## 概要

2社以上の企業を指定し、主要な財務指標・バリュエーション指標・成長性を横並びで比較するレポート生成機能を実装する。同業他社比較や投資候補の絞り込みに活用する。

## 背景

- 既存のmetric_percentile_ranking（20260320_1601）は1社を全企業中で位置づけるが、特定のN社を直接比較する機能はない
- company_financial_timeline_view（20260320_1600）は1社の時系列表示だが、複数社の並列比較はない
- ユースケースとして「同業3社を比較して最も成長性の高い企業を選ぶ」は極めて一般的な分析ワークフロー

## 実装内容

### Company モデルへのメソッド追加

```ruby
class Company
  # 指定された企業群の比較データを生成する
  # @param company_ids [Array<Integer>] 比較対象の企業IDリスト
  # @param fiscal_year_end [Date] 比較する決算期（デフォルト: 直近）
  # @param scope [Symbol] :consolidated or :non_consolidated
  # @return [Hash] 比較レポートデータ
  def self.get_comparison_report(company_ids:, fiscal_year_end: nil, scope: :consolidated)
  end
end
```

### 比較レポートの構成

1. **企業基本情報**
   - 企業名、証券コード、セクター、時価総額、市場区分

2. **成長性比較**
   - revenue_yoy, operating_income_yoy, net_income_yoy, eps_yoy
   - consecutive_revenue_growth, consecutive_profit_growth

3. **収益性比較**
   - operating_margin, ordinary_margin, net_margin
   - roe, roa

4. **財務健全性比較**
   - equity_ratio
   - free_cf, operating_cf_positive
   - cash_and_equivalents

5. **バリュエーション比較**
   - per, pbr, psr, dividend_yield, ev_ebitda（data_json由来）

6. **各指標での順位**
   - 比較対象企業群内でのランキング（N社中M位）

### 出力形式

- Hashとして返却し、CLI（rake task）やAPIから利用可能な形式
- 将来的にはWeb画面での表形式表示を想定

### テスト

- 2社比較のテスト（全指標が正しく並列で取得されること）
- 3社以上の比較テスト
- 決算期が揃わない企業の処理（直近の利用可能な期で代替）
- 指標データが欠損している企業の処理

## 備考

- analysis_query_layer（20260312_1000）が実装された後、ScreeningQueryの結果からシームレスに比較レポートに遷移する使い方を想定
- data_export_cli（20260310_1502）と連携し、`rake stockoverflow:compare[code1,code2,code3]` のようなCLI呼び出しも想定
