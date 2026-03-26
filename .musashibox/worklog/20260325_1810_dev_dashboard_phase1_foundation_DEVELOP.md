# WORKLOG: WEBダッシュボード Phase 1 - 基盤構築

- 作業日時: 2026-03-26
- 元TODO: `todo/20260325_1810_dev_dashboard_phase1_foundation_DEVELOP_done.md`

## 作業概要

WEBダッシュボードの基盤となるフロントエンドインフラ、CSSデザインシステム、レイアウト、ルーティング、コントローラーを構築した。

## 作業内容

### 1. JavaScript基盤の導入

- `bundle install` でgemの依存関係を解決
- `bin/rails importmap:install` でimportmap-railsのインフラを構築
  - `config/importmap.rb`, `app/javascript/application.js` を生成
- `bin/rails stimulus:install` でStimulus.jsを導入
  - `app/javascript/controllers/` ディレクトリとindex.js, application.jsを生成
- `bin/rails turbo:install` でTurbo Railsを導入

### 2. Chart.js導入

- `bin/importmap pin chart.js` でChart.js 4.5.1と依存ライブラリ(@kurkle/color)をvendor/javascriptにピン留め

### 3. CSSデザインシステム構築

ダークモードをデフォルトとするCSS変数ベースのデザインシステムを構築した。

**作成ファイル:**
- `base/variables.css` - ダーク/ライトモードのCSS custom properties（色、スペーシング、フォント、角丸）
- `base/reset.css` - 最小限のCSSリセット
- `base/typography.css` - フォント・テキストスタイル、value-positive/negativeユーティリティ
- `components/buttons.css` - ボタン（通常、primary、small、icon）
- `components/cards.css` - カード（section-card, metric-card, metric-grid）
- `components/tables.css` - テーブル（ストライプ、数値右寄せ、コンパクト）
- `components/forms.css` - フォーム（入力、セレクト、フィルターフォーム）
- `components/navigation.css` - ナビゲーション（nav-list, tab-nav）
- `components/badges.css` - バッジ（色バリエーション5種）
- `layouts/dashboard.css` - ダッシュボード2カラムグリッドレイアウト
- `layouts/sidebar.css` - サイドバーナビゲーション

PropshaftはCSS @importの自動パス解決をしないため、`stylesheet_link_tag :app` による全CSSファイル自動読み込みに依存する設計とした。

### 4. ダッシュボードレイアウト

- `app/views/layouts/dashboard.html.erb` を作成
  - ヘッダー（ロゴ + テーマ切替ボタン）+ サイドバー + メインコンテンツの2カラム構成
  - SVGアイコンをインラインで使用
  - Stimulusの`theme`コントローラーを接続
  - サイドバーにSearch / Companiesナビゲーションリンクを配置

### 5. テーマ切替（ダークモード/ライトモード）

- `app/javascript/controllers/theme_controller.js` を作成
  - `localStorage` にユーザー選択を永続化
  - `<html>` の `data-theme` 属性でテーマを切り替え
  - アイコン切替（太陽/月）を実装

### 6. ルーティング

`config/routes.rb` を更新:
- `root` → `dashboard#index` (→ dashboard_root_path にリダイレクト)
- `namespace :dashboard` 以下:
  - `search#index`, `search#execute`
  - `presets` CRUD (index, create, show, destroy)
  - `companies` (index, show) + member routes (financials, metrics, quotes, compare)

### 7. コントローラー

- `DashboardController` - ルートコントローラー（dashboardレイアウト使用、indexからリダイレクト）
- `Dashboard::BaseController` - ダッシュボード名前空間の基底クラス
- `Dashboard::SearchController` - 検索ダッシュボード
- `Dashboard::CompaniesController` - 企業一覧・詳細
- `Dashboard::PresetsController` - 検索条件プリセット

### 8. プレースホルダービュー

後続フェーズで実装予定の各画面のプレースホルダーを作成:
- `dashboard/search/index.html.erb`
- `dashboard/companies/index.html.erb`
- `dashboard/companies/show.html.erb`

## 検証

- `bin/rails runner` でアプリケーションの起動を確認
- `bin/rails routes` で全ルートの定義を確認
- Propshaftが全12 CSSファイルを検出していることを確認
- RSpec全277テストがパス（既存機能への影響なし）

## 考えたこと

- PropshaftはCSS `@import` のパスをフィンガープリント付きURLに書き換えないため、CSS @importは使わず `stylesheet_link_tag :app` による全ファイル自動読み込みに依存した。CSS custom propertiesは計算時に解決されるためファイル読み込み順序の問題は発生しない。
- コントローラーの名前空間として `Dashboard::BaseController` を導入し、レイアウト指定の重複を避けた。
- hello_controller.js（Stimulus自動生成のサンプル）は不要なため削除した。
