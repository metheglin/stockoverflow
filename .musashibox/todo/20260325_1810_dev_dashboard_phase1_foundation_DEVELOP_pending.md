# DEVELOP: WEBダッシュボード Phase 1 - 基盤構築

## 概要

WEBダッシュボードの基盤となるレイアウト、CSSデザインシステム（ダークモード）、フロントエンドライブラリの導入、共通ナビゲーションを構築する。

## 元計画

- `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 前提・依存

- なし（最初に着手すべきフェーズ）

---

## 1. フロントエンドライブラリの導入

### 1-1. Chart.js の導入

グラフ描画に **Chart.js** を使用する。importmap経由で導入する。

```bash
bin/importmap pin chart.js
```

Chart.jsを選定した理由:
- importmap (ESM) で直接利用可能
- 軽量で、折れ線グラフ・棒グラフ・複合グラフなど必要なグラフ種類を網羅
- ダークモード対応のカスタマイズが容易（CSS変数経由でフォントカラー・グリッドカラーを指定可能）

### 1-2. Stimulus コントローラーの基本構成

`app/javascript/controllers/` にStimulusコントローラーを配置する。Rails 8.1のデフォルトではimportmap + stimulus-rails によって自動ロードされる。

```bash
bin/rails stimulus:install  # まだ実行されていなければ
```

ディレクトリ構成:

```
app/javascript/
├── application.js
└── controllers/
    ├── index.js
    ├── theme_controller.js       # ダークモード切り替え
    └── (以降のフェーズで追加)
```

---

## 2. CSSデザインシステム（ダークモードベース）

### 2-1. CSS変数によるテーマ定義

`app/assets/stylesheets/` 配下にCSSファイルを作成する。

**ファイル構成:**

```
app/assets/stylesheets/
├── application.css        # マニフェスト（@importで各ファイルを読み込み）
├── base/
│   ├── reset.css          # 最小限のリセット
│   ├── variables.css      # CSS custom properties（テーマ変数）
│   └── typography.css     # フォント・テキストスタイル
├── components/
│   ├── buttons.css
│   ├── cards.css
│   ├── tables.css
│   ├── forms.css
│   ├── navigation.css
│   └── badges.css
└── layouts/
    ├── dashboard.css      # ダッシュボード共通レイアウト
    └── sidebar.css        # サイドバーナビゲーション
```

### 2-2. CSS変数定義 (`variables.css`)

ダークモードをデフォルトとし、ライトモードもCSS変数の切り替えで対応する。

```css
:root {
  /* ダークモード（デフォルト） */
  --color-bg-primary: #0d1117;
  --color-bg-secondary: #161b22;
  --color-bg-tertiary: #21262d;
  --color-bg-hover: #30363d;

  --color-border-primary: #30363d;
  --color-border-secondary: #21262d;

  --color-text-primary: #e6edf3;
  --color-text-secondary: #8b949e;
  --color-text-muted: #6e7681;

  --color-accent-blue: #58a6ff;
  --color-accent-green: #3fb950;
  --color-accent-red: #f85149;
  --color-accent-yellow: #d29922;
  --color-accent-purple: #bc8cff;

  /* チャート用カラーパレット */
  --chart-color-1: #58a6ff;
  --chart-color-2: #3fb950;
  --chart-color-3: #f85149;
  --chart-color-4: #d29922;
  --chart-color-5: #bc8cff;
  --chart-color-6: #f778ba;
  --chart-grid: rgba(110, 118, 129, 0.3);
  --chart-text: #8b949e;

  /* スペーシング */
  --spacing-xs: 4px;
  --spacing-sm: 8px;
  --spacing-md: 16px;
  --spacing-lg: 24px;
  --spacing-xl: 32px;

  /* フォント */
  --font-family-base: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans JP", Helvetica, Arial, sans-serif;
  --font-family-mono: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
  --font-size-xs: 0.75rem;
  --font-size-sm: 0.875rem;
  --font-size-base: 1rem;
  --font-size-lg: 1.125rem;
  --font-size-xl: 1.25rem;

  /* ボーダー半径 */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
}

/* ライトモード */
[data-theme="light"] {
  --color-bg-primary: #ffffff;
  --color-bg-secondary: #f6f8fa;
  --color-bg-tertiary: #eaeef2;
  --color-bg-hover: #d0d7de;

  --color-border-primary: #d0d7de;
  --color-border-secondary: #eaeef2;

  --color-text-primary: #1f2328;
  --color-text-secondary: #656d76;
  --color-text-muted: #8b949e;

  --color-accent-blue: #0969da;
  --color-accent-green: #1a7f37;
  --color-accent-red: #cf222e;
  --color-accent-yellow: #9a6700;
  --color-accent-purple: #8250df;

  --chart-color-1: #0969da;
  --chart-color-2: #1a7f37;
  --chart-color-3: #cf222e;
  --chart-color-4: #9a6700;
  --chart-color-5: #8250df;
  --chart-color-6: #bf3989;
  --chart-grid: rgba(208, 215, 222, 0.5);
  --chart-text: #656d76;
}
```

### 2-3. ダークモード切り替えの仕組み

- `<html>` 要素に `data-theme` 属性を付与
- デフォルトは属性なし（= ダークモード）
- `data-theme="light"` を付与するとライトモード
- `localStorage` でユーザーの選択を永続化する
- Stimulusコントローラー `theme_controller.js` で切り替えを制御

```javascript
// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    const saved = localStorage.getItem("theme")
    if (saved === "light") {
      document.documentElement.setAttribute("data-theme", "light")
    }
    this.updateIcon()
  }

  toggle() {
    const current = document.documentElement.getAttribute("data-theme")
    if (current === "light") {
      document.documentElement.removeAttribute("data-theme")
      localStorage.removeItem("theme")
    } else {
      document.documentElement.setAttribute("data-theme", "light")
      localStorage.setItem("theme", "light")
    }
    this.updateIcon()
  }

  updateIcon() {
    // ターゲットがあればアイコンを更新（太陽/月の切り替え等）
  }
}
```

---

## 3. レイアウトとナビゲーション

### 3-1. ダッシュボードレイアウト

`app/views/layouts/dashboard.html.erb` を新規作成する。
サイドバー + メインコンテンツの2カラム構成。

```
+--------------------------------------------------+
| [Logo]  StockOverflow                    [Theme]  |
+--------+-----------------------------------------+
|        |                                         |
| Nav    |   Main Content Area                     |
|        |                                         |
| Search |   (yield)                               |
| Detail |                                         |
|        |                                         |
+--------+-----------------------------------------+
```

サイドバーのナビゲーション項目:

| 項目 | パス | 説明 |
|------|------|------|
| Search | `/dashboard/search` | 検索ダッシュボード |
| Companies | `/dashboard/companies` | 企業一覧（簡易検索） |
| Company Detail | `/dashboard/companies/:id` | 企業詳細ダッシュボード |

### 3-2. ルーティング設計

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "dashboard#index"

  namespace :dashboard do
    root "search#index"

    # 検索ダッシュボード
    resources :search, only: [:index] do
      collection do
        post :execute     # 検索実行（Turbo Stream）
      end
    end

    # 検索条件プリセット
    resources :presets, only: [:index, :create, :show, :destroy]

    # 企業詳細ダッシュボード
    resources :companies, only: [:index, :show] do
      member do
        get :financials   # 財務データタブ（Turbo Frame）
        get :metrics      # 指標タブ（Turbo Frame）
        get :quotes       # 株価タブ（Turbo Frame）
        get :compare      # 比較ビュー
      end
    end
  end

  # 既存
  get "up" => "rails/health#show", as: :rails_health_check
end
```

### 3-3. ダッシュボードルートコントローラー

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  layout "dashboard"

  def index
    redirect_to dashboard_root_path
  end
end
```

---

## 4. 共通UIコンポーネント（CSS）

以下のCSSコンポーネントを最低限実装する:

### テーブル (`tables.css`)
- ダークモード対応の縞模様テーブル
- セルの数値右寄せ
- 増減を色分けするユーティリティクラス (`.value-positive`, `.value-negative`)

### カード (`cards.css`)
- メトリクスカード（数値ハイライト用）
- セクションカード（グラフ・テーブルのコンテナ）

### フォーム (`forms.css`)
- セレクトボックス、テキストインプット、ボタンのダークモード対応スタイル
- フィルター条件入力向けのコンパクトなフォームスタイル

### バッジ (`badges.css`)
- セクター表示、市場区分表示用の小さなラベル

---

## 5. ファイル構成

### 新規作成

| ファイル | 内容 |
|---------|------|
| `app/views/layouts/dashboard.html.erb` | ダッシュボードレイアウト |
| `app/controllers/dashboard_controller.rb` | ルートコントローラー |
| `app/assets/stylesheets/base/reset.css` | CSSリセット |
| `app/assets/stylesheets/base/variables.css` | テーマ変数 |
| `app/assets/stylesheets/base/typography.css` | タイポグラフィ |
| `app/assets/stylesheets/components/buttons.css` | ボタンスタイル |
| `app/assets/stylesheets/components/cards.css` | カードスタイル |
| `app/assets/stylesheets/components/tables.css` | テーブルスタイル |
| `app/assets/stylesheets/components/forms.css` | フォームスタイル |
| `app/assets/stylesheets/components/navigation.css` | ナビゲーション |
| `app/assets/stylesheets/components/badges.css` | バッジスタイル |
| `app/assets/stylesheets/layouts/dashboard.css` | ダッシュボードレイアウト |
| `app/assets/stylesheets/layouts/sidebar.css` | サイドバー |
| `app/javascript/controllers/theme_controller.js` | テーマ切替 |

### 既存変更

| ファイル | 変更内容 |
|---------|---------|
| `config/routes.rb` | ダッシュボードルーティング追加 |
| `app/assets/stylesheets/application.css` | @import でCSS読み込み |

---

## 6. 実装順序

1. CSSファイル群の作成（variables.css → reset.css → 各コンポーネント）
2. `application.css` に@importを追加
3. `dashboard.html.erb` レイアウト作成
4. Stimulus install確認 + `theme_controller.js` 作成
5. Chart.js をimportmapで追加
6. `config/routes.rb` にルート追加
7. `DashboardController` 作成
8. ブラウザで表示確認
