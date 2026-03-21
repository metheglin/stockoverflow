# DEVELOP: スクリーニング結果のテーブル表示フォーマッター

## 概要

分析クエリレイヤー（20260312_1000）のQueryObjectが返すデータ構造を、コンソール上で読みやすいテーブル形式で表示し、またCSVとして出力できるフォーマッターを実装する。

## 背景・動機

分析クエリレイヤーのQueryObject（ConsecutiveGrowthQuery, CashFlowTurnaroundQuery, FinancialTimelineQuery, ScreeningQuery）は `Array<Hash>` を返す設計だが、これを人間が読める形で表示する手段が存在しない。`rails console` で実行しても、生のHashやActiveRecordオブジェクトが表示されるだけで、一覧性に欠ける。

プロジェクトの目的「注目すべき企業や情報を一覧できるシステム」を達成するには、結果を見やすく表示する仕組みが不可欠。

## 実装方針

### 配置先

`app/lib/screening_result_formatter.rb`

### 機能

1. **コンソールテーブル出力**
   - カラム幅の自動調整
   - 数値のフォーマット（パーセント、通貨、小数桁数）
   - 企業名・証券コードの表示
   - 行番号の付与

2. **CSV出力**
   - UTF-8 BOM付き（Excel互換）
   - カラムヘッダー付き
   - ファイル出力先指定可能

3. **表示カラムのカスタマイズ**
   - QueryObjectの種類に応じたデフォルトカラムセット
   - ユーザーによるカラム選択

### インターフェース案

```ruby
class ScreeningResultFormatter
  def initialize(results, columns: nil, format: :table)
    @results = results
    @columns = columns || default_columns
    @format = format
  end

  def render
    case @format
    when :table then render_table
    when :csv then render_csv
    end
  end

  def save_csv(path)
    # CSV出力
  end
end
```

### 使用例

```ruby
results = Company::ConsecutiveGrowthQuery.new(min_periods: 6).execute
puts ScreeningResultFormatter.new(results).render

# CSV出力
ScreeningResultFormatter.new(results, format: :csv).save_csv("tmp/growth_companies.csv")
```

## 前提・依存

- 分析クエリレイヤー（20260312_1000）の実装完了後に実装可能
- 外部gemは使用せず、Ruby標準のString#ljust等で実装する

## テスト

- `render_table` メソッドが正しくフォーマットされた文字列を返すこと
- `render_csv` メソッドが正しいCSV文字列を返すこと
- `save_csv` メソッドがファイルを正しく出力すること
- 数値フォーマット（パーセント表示、桁区切り）が正しいこと
