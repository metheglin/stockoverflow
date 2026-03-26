# DEVELOP: WEBダッシュボード Phase 5 - 詳細ダッシュボード フロントエンド

## 概要

特定企業の詳細ダッシュボードのフロントエンド（企業一覧・検索、企業詳細画面のグラフ・テーブル・タブUI、比較ビュー）を実装する。

## 元計画

- `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 前提・依存

- Phase 1（基盤構築）が完了していること（CSS、Chart.js導入済み）
- Phase 4（詳細バックエンド）が完了していること

---

## 1. 画面構成

### 1-1. 企業一覧画面 (`/dashboard/companies`)

簡易的な企業検索・一覧画面。検索ダッシュボードとは異なり、テキスト検索で企業を探す用途。

```
+------------------------------------------------------------------+
| 企業検索                                                          |
| [証券コード・企業名で検索...               ] [検索]               |
+------------------------------------------------------------------+
| 証券コード | 企業名          | セクター       | 市場    |         |
| 7203      | トヨタ自動車     | 輸送用機器      | プライム | [詳細]  |
| 6758      | ソニーグループ   | 電気機器        | プライム | [詳細]  |
| ...                                                               |
+------------------------------------------------------------------+
```

- Turbo Frameで検索結果をインライン更新
- 行クリックまたは「詳細」ボタンで企業詳細画面へ遷移

### 1-2. 企業詳細画面 (`/dashboard/companies/:id`)

```
+------------------------------------------------------------------+
| [<戻る]  7203 トヨタ自動車 (Toyota Motor Corp.)                   |
| 輸送用機器 | プライム | TOPIX Large70                              |
+------------------------------------------------------------------+
| スコープ: [連結 v]  期間: [通期 v]                                |
+------------------------------------------------------------------+
| 最新サマリー                                                      |
| +-------------------+-------------------+-------------------+     |
| | 売上高            | 営業利益          | 純利益            |     |
| | 37.15兆           | 2.73兆           | 2.45兆            |     |
| | +15.2% YoY        | +22.1% YoY       | +18.5% YoY       |     |
| +-------------------+-------------------+-------------------+     |
| | ROE               | PER               | 配当利回り        |     |
| | 12.3%             | 10.2x             | 2.8%              |     |
| +-------------------+-------------------+-------------------+     |
| | 総合スコア        | 成長スコア        | 品質スコア        |     |
| | 78.5              | 72.3              | 85.1              |     |
| +-------------------+-------------------+-------------------+     |
+------------------------------------------------------------------+
| タブ:  [財務データ]  [指標推移]  [株価]  [比較]                   |
+------------------------------------------------------------------+
| (タブ内容: Turbo Frame で切り替え)                                |
|                                                                   |
| 財務データタブの場合:                                              |
| +--------------------------------------------------------------+ |
| |  [売上・利益推移グラフ]           | 数値テーブル              | |
| |  +---------+                      | FY   | 売上 | 営利 |純利 | |
| |  |  Chart  |                      | 2024 | xxx  | xxx  |xxx  | |
| |  |         |                      | 2023 | xxx  | xxx  |xxx  | |
| |  +---------+                      | 2022 | xxx  | xxx  |xxx  | |
| +--------------------------------------------------------------+ |
| +--------------------------------------------------------------+ |
| |  [キャッシュフロー推移グラフ]     | 数値テーブル              | |
| |  +---------+                      | FY   | 営CF | 投CF |FCF  | |
| |  |  Chart  |                      |      |      |      |     | |
| |  +---------+                      |      |      |      |     | |
| +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
```

---

## 2. タブ構成

Turbo Frameを使ったタブ切り替え。各タブは遅延読み込み (lazy loading) でアクセス時にサーバーからフレーム内容を取得する。

### 2-1. 財務データタブ (`financials`)

**内容:**
- 売上・利益推移グラフ（複合: 売上高=棒、営業利益・純利益=折れ線）
- キャッシュフロー推移グラフ（棒グラフ）
- 各グラフの横に数値テーブルを並列配置

### 2-2. 指標推移タブ (`metrics`)

**内容:**
- 成長率推移グラフ（折れ線: revenue_yoy, operating_income_yoy, net_income_yoy）
- 収益性指標推移グラフ（折れ線: roe, roa, operating_margin, net_margin）
- バリュエーション推移グラフ（折れ線: per, pbr）
- 1株あたり指標推移グラフ（折れ線: eps, bps）
- セクター内比較バー（各指標のセクター内パーセンタイル表示）

### 2-3. 株価タブ (`quotes`)

**内容:**
- 株価チャート（折れ線: 終値 + 移動平均線 25日/75日/200日）
- 出来高チャート（棒グラフ）
- 期間セレクター: [1M] [3M] [6M] [1Y] [3Y] [ALL]

### 2-4. 比較タブ (`compare`)

**内容:**
- 表示したいグラフを選択できるチェックボックスリスト
- 選択されたグラフを2列グリッドで並列表示
- 一画面で複数の視点を同時に確認できるビュー

---

## 3. Stimulus コントローラー

### 3-1. chart_controller.js

Chart.jsのグラフ描画を担当する汎用Stimulusコントローラー。

**配置先**: `app/javascript/controllers/chart_controller.js`

**仕組み:**
- `data-chart-url-value` にJSON APIエンドポイントのURLを指定
- `data-chart-type-value` でグラフタイプ (line, bar, mixed) を指定
- `connect()` 時にfetchしてChart.jsインスタンスを生成
- CSS変数からテーマカラーを読み取り、Chart.jsのオプションに反映
- テーマ切り替え時にグラフカラーも更新

```javascript
// app/javascript/controllers/chart_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    type: { type: String, default: "line" },
  }

  connect() {
    this.loadChart()
    // テーマ変更イベントを監視
    document.addEventListener("theme:changed", () => this.updateColors())
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  async loadChart() {
    const response = await fetch(this.urlValue)
    const data = await response.json()
    this.renderChart(data)
  }

  renderChart(data) {
    const ctx = this.element.querySelector("canvas").getContext("2d")
    const colors = this.getThemeColors()

    // Chart.jsインスタンスを生成
    // data.datasets の各datasetにカラーを付与
    // グリッド・ティックのカラーをCSS変数から取得
  }

  getThemeColors() {
    const style = getComputedStyle(document.documentElement)
    return {
      colors: [
        style.getPropertyValue("--chart-color-1").trim(),
        style.getPropertyValue("--chart-color-2").trim(),
        style.getPropertyValue("--chart-color-3").trim(),
        style.getPropertyValue("--chart-color-4").trim(),
        style.getPropertyValue("--chart-color-5").trim(),
        style.getPropertyValue("--chart-color-6").trim(),
      ],
      grid: style.getPropertyValue("--chart-grid").trim(),
      text: style.getPropertyValue("--chart-text").trim(),
    }
  }

  updateColors() {
    if (this.chart) {
      // Chart.jsのoptionsを更新してupdate()
    }
  }
}
```

### 3-2. tabs_controller.js

タブ切り替えUIの制御。

**配置先**: `app/javascript/controllers/tabs_controller.js`

**責務:**
- アクティブタブの視覚的ハイライト
- Turbo Frameの遅延読み込みトリガー
- URLハッシュとの同期（ブラウザバック対応）

### 3-3. company_search_controller.js

企業一覧画面のインクリメンタル検索を制御。

**配置先**: `app/javascript/controllers/company_search_controller.js`

**責務:**
- テキスト入力のデバウンス（300ms）
- Turbo Frameによる検索結果の更新
- 検索中のローディング表示

### 3-4. period_selector_controller.js

株価タブの期間セレクター。

**配置先**: `app/javascript/controllers/period_selector_controller.js`

**責務:**
- 期間ボタンクリック時にグラフデータを再取得
- アクティブ期間の視覚的ハイライト

---

## 4. ビューテンプレート

### 4-1. 企業一覧

| ファイル | 内容 |
|---------|------|
| `app/views/dashboard/companies/index.html.erb` | 企業一覧画面 |
| `app/views/dashboard/companies/_company_list.html.erb` | 一覧テーブルパーシャル（Turbo Frame内） |

### 4-2. 企業詳細

| ファイル | 内容 |
|---------|------|
| `app/views/dashboard/companies/show.html.erb` | 詳細画面メイン |
| `app/views/dashboard/companies/_summary_cards.html.erb` | 最新サマリーカード |
| `app/views/dashboard/companies/_financials.html.erb` | 財務データタブ |
| `app/views/dashboard/companies/_metrics.html.erb` | 指標推移タブ |
| `app/views/dashboard/companies/_quotes.html.erb` | 株価タブ |
| `app/views/dashboard/companies/compare.html.erb` | 比較ビュー |

### 4-3. 共通パーツ

| ファイル | 内容 |
|---------|------|
| `app/views/dashboard/companies/_chart_section.html.erb` | グラフ+テーブルのセクションパーシャル |
| `app/views/dashboard/companies/_data_table.html.erb` | 時系列数値テーブルパーシャル |
| `app/views/dashboard/companies/_sector_position.html.erb` | セクター内ポジションバーパーシャル |

---

## 5. グラフとテーブルの並列レイアウト

要件「グラフをつかって表示。ただ、表などで数値情報も併記すること」に対応するレイアウト。

各セクションを以下の構造で実装:

```html
<div class="chart-section">
  <h3 class="chart-section__title">売上・利益推移</h3>
  <div class="chart-section__body">
    <div class="chart-section__chart"
         data-controller="chart"
         data-chart-url-value="/dashboard/companies/123/chart_data?chart_type=revenue_profit">
      <canvas></canvas>
    </div>
    <div class="chart-section__table">
      <%= render "dashboard/companies/data_table",
                 timeline: @summary.timeline,
                 columns: [:net_sales, :operating_income, :net_income] %>
    </div>
  </div>
</div>
```

CSSで横並び:
```css
.chart-section__body {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: var(--spacing-md);
}
```

---

## 6. セクター内比較の可視化

各指標について、セクター内でのパーセンタイルを水平バーで表現する。

```html
<!-- _sector_position.html.erb -->
<div class="sector-position">
  <div class="sector-position__label">ROE</div>
  <div class="sector-position__bar">
    <div class="sector-position__fill" style="width: 78%">
      <span class="sector-position__value">12.3%</span>
    </div>
    <div class="sector-position__median-marker" style="left: 45%"
         title="セクター中央値: 8.2%"></div>
  </div>
  <div class="sector-position__percentile">上位22%</div>
</div>
```

---

## 7. 数値テーブルのフォーマット

### DashboardHelper に追加するメソッド

```ruby
# 金額を読みやすい形式にフォーマット
# 100_000_000 => "1.00億"
# 1_000_000_000_000 => "1.00兆"
def format_amount(value)
  return "-" if value.nil?
  if value.abs >= 1_000_000_000_000
    "#{(value / 1_000_000_000_000.0).round(2)}兆"
  elsif value.abs >= 100_000_000
    "#{(value / 100_000_000.0).round(2)}億"
  elsif value.abs >= 10_000
    "#{(value / 10_000.0).round(1)}万"
  else
    value.to_s
  end
end

# パーセント表示
def format_percent(value)
  return "-" if value.nil?
  "#{(value * 100).round(1)}%"
end

# 倍率表示
def format_ratio(value)
  return "-" if value.nil?
  "#{value.round(2)}x"
end
```

---

## 8. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/views/dashboard/companies/index.html.erb` | 企業一覧 |
| `app/views/dashboard/companies/_company_list.html.erb` | 一覧パーシャル |
| `app/views/dashboard/companies/show.html.erb` | 企業詳細 |
| `app/views/dashboard/companies/_summary_cards.html.erb` | サマリーカード |
| `app/views/dashboard/companies/_financials.html.erb` | 財務タブ |
| `app/views/dashboard/companies/_metrics.html.erb` | 指標タブ |
| `app/views/dashboard/companies/_quotes.html.erb` | 株価タブ |
| `app/views/dashboard/companies/compare.html.erb` | 比較ビュー |
| `app/views/dashboard/companies/_chart_section.html.erb` | グラフセクション |
| `app/views/dashboard/companies/_data_table.html.erb` | 数値テーブル |
| `app/views/dashboard/companies/_sector_position.html.erb` | セクター比較バー |
| `app/javascript/controllers/chart_controller.js` | Chart.js描画 |
| `app/javascript/controllers/tabs_controller.js` | タブ切り替え |
| `app/javascript/controllers/company_search_controller.js` | 企業検索 |
| `app/javascript/controllers/period_selector_controller.js` | 期間選択 |

### 既存変更

| ファイル | 変更内容 |
|---------|---------|
| `app/helpers/dashboard_helper.rb` | format_amount, format_percent, format_ratio 追加 |
| `app/assets/stylesheets/components/` | チャートセクション・セクター比較バー等のCSS追加 |

---

## 9. 実装順序

1. `chart_controller.js` 実装（Chart.js統合の中核）
2. `tabs_controller.js` 実装
3. 企業一覧画面ビュー作成 + `company_search_controller.js`
4. 企業詳細画面ビュー作成（`show.html.erb` + `_summary_cards.html.erb`）
5. 財務データタブ (`_financials.html.erb` + `_chart_section.html.erb` + `_data_table.html.erb`)
6. 指標推移タブ (`_metrics.html.erb` + `_sector_position.html.erb`)
7. 株価タブ (`_quotes.html.erb` + `period_selector_controller.js`)
8. 比較ビュー (`compare.html.erb`)
9. `DashboardHelper` にフォーマットメソッド追加
10. CSS追加（チャートセクション、セクター比較バー等）
11. テーマ変更時のグラフカラー更新の動作確認
12. 全体の動作確認・微調整

---

## 10. 比較ビューの設計詳細

「いろんな軸で比較ができるようなUI」の要件に対応する。

### 比較方法1: グラフ選択式（本フェーズで実装）

ユーザーが表示したいグラフを選択し、2列グリッドで並列表示。

- チェックボックスリスト: 売上推移 / 成長率 / 収益性 / CF / バリュエーション / EPS・BPS / 株価
- 選択されたグラフが2列で表示される
- 一画面で「売上の成長と収益性の変化を同時に確認」のようなユースケースに対応

### 比較方法2: 企業間比較（将来拡張）

複数企業を同一グラフ上にプロットして比較する機能。
本フェーズではスコープ外とするが、将来対応を見据えて `chart_data` APIのインターフェースを設計しておく。

将来のAPIイメージ:
```
GET /dashboard/companies/compare_multi?ids=123,456,789&chart_type=roe
```
