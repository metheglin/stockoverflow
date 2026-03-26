# DEVELOP: WEBダッシュボード Phase 3 - 検索ダッシュボード フロントエンド

## 概要

検索ダッシュボードのフロントエンド（動的フィルタUI、結果テーブル、プリセット保存・読み込みUI）を実装する。Hotwire (Turbo + Stimulus) を用いたSPA的な体験を構築する。

## 元計画

- `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 前提・依存

- Phase 1（基盤構築）が完了していること
- Phase 2（検索バックエンド）が完了していること

---

## 1. 画面構成

### 1-1. 検索ダッシュボード画面 (`/dashboard/search`)

```
+------------------------------------------------------------------+
| [プリセット選択ドロップダウン]   [条件リセット]   [保存]           |
+------------------------------------------------------------------+
| フィルタ条件エリア                                                |
| +--------------------------------------------------------------+ |
| | 論理演算: [AND v]                                            | |
| | +----------------------------------------------------------+ | |
| | | [x] 指標: [ROE v]  演算: [>=]  値: [0.10]     [削除]     | | |
| | +----------------------------------------------------------+ | |
| | | [x] 指標: [連続増収期数 v] 演算: [>=] 値: [3]  [削除]    | | |
| | +----------------------------------------------------------+ | |
| | | [x] 属性: [市場区分 v]  値: [プライム v]       [削除]     | | |
| | +----------------------------------------------------------+ | |
| |                                        [+ 条件を追加]        | |
| +--------------------------------------------------------------+ |
|                                                                   |
| [検索実行]                                                        |
+------------------------------------------------------------------+
| 結果テーブル（Turbo Frameで差し替え）                             |
| +--------------------------------------------------------------+ |
| | 証券コード | 社名     | セクター  | ROE    | 増収率  | Score | |
| | 7203      | トヨタ... | 輸送用.. | 12.3%  | +15.2% | 78.5  | |
| | 6758      | ソニー... | 電気機.. | 18.7%  | +22.1% | 85.2  | |
| | ...                                                          | |
| +--------------------------------------------------------------+ |
| 結果: 142件  (100件表示)                                         |
+------------------------------------------------------------------+
```

---

## 2. Stimulus コントローラー

### 2-1. filter_builder_controller.js

フィルタ条件の動的追加・削除・編集を制御する中核コントローラー。

**配置先**: `app/javascript/controllers/filter_builder_controller.js`

**責務:**
- 条件行の動的追加（テンプレートからcloneして挿入）
- 条件行の削除
- 条件タイプに応じた入力フォームの切り替え（指標名選択 → 演算子・値のフォームを動的に変更）
- 論理演算子（AND/OR）の切り替え
- 全条件をJSON形式に集約し、hidden fieldまたはfetch bodyとして送信
- 条件のバリデーション（空の条件行を除外）

**データフロー:**

```
ユーザー操作
  ↓
Stimulus controller: DOM操作（条件行追加/削除/変更）
  ↓
検索実行ボタンクリック
  ↓
Stimulus controller: DOM → conditions JSON を構築
  ↓
Turbo (fetch POST /dashboard/search/execute)
  ↓
サーバー: ConditionExecutor 実行
  ↓
Turbo Stream: 結果テーブル差し替え
```

**主要なメソッド:**

```javascript
// 条件行を追加
addCondition()

// 条件行を削除
removeCondition(event)

// 条件タイプ変更時のフォーム切り替え
changeConditionType(event)

// 全条件をJSONに集約
buildConditionsJson()

// 検索実行
executeSearch()
```

### 2-2. preset_manager_controller.js

プリセットの選択・保存を制御するコントローラー。

**配置先**: `app/javascript/controllers/preset_manager_controller.js`

**責務:**
- プリセット選択時に条件をフィルタビルダーに復元
- 現在の条件をプリセットとして保存（モーダルで名前入力）
- プリセット一覧のロード

### 2-3. result_table_controller.js

結果テーブルのインタラクションを制御する簡易コントローラー。

**配置先**: `app/javascript/controllers/result_table_controller.js`

**責務:**
- 行クリックで企業詳細ページへ遷移
- 数値のフォーマット（パーセント、通貨等）
- 増減の色分け表示

---

## 3. ビューテンプレート

### 3-1. 検索画面

**ファイル**: `app/views/dashboard/search/index.html.erb`

主要な構成:
- プリセットセレクター（上部）
- フィルタビルダー（中央、Stimulusで制御）
- 結果テーブル（下部、Turbo Frame `search_results` で囲む）

### 3-2. 結果テーブル (Turbo Stream)

**ファイル**: `app/views/dashboard/search/execute.turbo_stream.erb`

```erb
<%= turbo_stream.replace "search_results" do %>
  <%= render "dashboard/search/results_table",
             results: @results,
             display_columns: @display_columns %>
<% end %>
```

### 3-3. 結果テーブルパーシャル

**ファイル**: `app/views/dashboard/search/_results_table.html.erb`

- 動的カラム表示: `display_columns` パラメータに基づいて表示列を決定
- 数値フォーマット: ヘルパーメソッドで % 表示、カンマ区切り等
- 増減の色分け: positive/negative クラスを付与
- 各行は企業詳細ページへのリンク

### 3-4. フィルタ条件行テンプレート

**ファイル**: `app/views/dashboard/search/_condition_row.html.erb`

Stimulusで動的にcloneされるテンプレート要素。`<template>` タグ内に配置する。

---

## 4. ビューヘルパー

### 4-1. DashboardHelper

**ファイル**: `app/helpers/dashboard_helper.rb`

```ruby
module DashboardHelper
  # 指標値を適切にフォーマットする
  # @param value [Numeric, nil] 値
  # @param format_type [Symbol] :percent, :number, :currency, :integer, :score
  # @return [String] フォーマット済み文字列
  def format_metric_value(value, format_type)
    # ...
  end

  # 増減に応じたCSSクラスを返す
  def value_color_class(value)
    return "" if value.nil?
    value >= 0 ? "value-positive" : "value-negative"
  end

  # フィルタ可能な指標のオプション一覧を返す
  # セレクトボックスで使用
  def metric_filter_options
    # [["ROE", "roe"], ["ROA", "roa"], ...]
  end

  # 企業属性のオプション一覧を返す
  def company_attribute_filter_options
    # [["セクター(33分類)", "sector_33_code"], ["市場区分", "market_code"], ...]
  end
end
```

---

## 5. 指標のラベル定義

UIに表示する指標名の日本語ラベルを定義する。

**配置先**: `config/locales/metrics.ja.yml` または `app/models/concerns/metric_labels.rb`

```yaml
# config/locales/metrics.ja.yml
ja:
  metrics:
    revenue_yoy: "売上高成長率(YoY)"
    operating_income_yoy: "営業利益成長率(YoY)"
    net_income_yoy: "純利益成長率(YoY)"
    eps_yoy: "EPS成長率(YoY)"
    roe: "ROE(自己資本利益率)"
    roa: "ROA(総資産利益率)"
    operating_margin: "営業利益率"
    net_margin: "純利益率"
    consecutive_revenue_growth: "連続増収期数"
    consecutive_profit_growth: "連続増益期数"
    per: "PER(株価収益率)"
    pbr: "PBR(株価純資産倍率)"
    psr: "PSR(株価売上高倍率)"
    dividend_yield: "配当利回り"
    composite_score: "総合スコア"
    growth_score: "成長スコア"
    quality_score: "品質スコア"
    value_score: "バリュースコア"
    free_cf: "フリーキャッシュフロー"
    operating_cf_positive: "営業CF正"
    investing_cf_negative: "投資CF負"
    free_cf_positive: "FCF正"
    # ... 他の指標
  company_attributes:
    sector_17_code: "セクター(17分類)"
    sector_33_code: "セクター(33分類)"
    market_code: "市場区分"
    scale_category: "規模区分"
```

---

## 6. プリセット保存モーダル

現在のフィルタ条件を名前付きプリセットとして保存するためのモーダルUI。

- Turbo Frame またはシンプルな `<dialog>` 要素で実装
- 名前（必須）と説明（任意）を入力
- 保存ボタンで `POST /dashboard/presets` に送信
- 保存成功後、プリセットドロップダウンを更新

---

## 7. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/views/dashboard/search/index.html.erb` | 検索画面 |
| `app/views/dashboard/search/execute.turbo_stream.erb` | 結果Turbo Stream |
| `app/views/dashboard/search/_results_table.html.erb` | 結果テーブルパーシャル |
| `app/views/dashboard/search/_condition_row.html.erb` | 条件行テンプレート |
| `app/views/dashboard/search/_preset_save_modal.html.erb` | 保存モーダル |
| `app/views/dashboard/presets/index.html.erb` | プリセット一覧 |
| `app/views/dashboard/presets/show.html.erb` | プリセット実行結果 |
| `app/javascript/controllers/filter_builder_controller.js` | フィルタビルダー |
| `app/javascript/controllers/preset_manager_controller.js` | プリセット管理 |
| `app/javascript/controllers/result_table_controller.js` | 結果テーブル |
| `app/helpers/dashboard_helper.rb` | ビューヘルパー |
| `config/locales/metrics.ja.yml` | 指標ラベル |

---

## 8. 実装順序

1. 指標ラベル定義ファイル (`metrics.ja.yml`) 作成
2. `DashboardHelper` 実装
3. 検索画面ビュー (`index.html.erb`) 作成（静的版）
4. `filter_builder_controller.js` 実装
5. 結果テーブルパーシャル作成
6. `execute.turbo_stream.erb` 作成
7. Turbo Stream で検索実行 → 結果表示の動作確認
8. `preset_manager_controller.js` 実装
9. プリセット保存モーダル作成
10. プリセット一覧・実行結果画面作成
11. `result_table_controller.js` 実装（数値フォーマット・色分け・行クリック）
12. 全体の動作確認・微調整
