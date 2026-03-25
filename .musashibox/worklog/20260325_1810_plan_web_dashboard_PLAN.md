# WORKLOG: WEBダッシュボード開発計画

**作業日時**: 2026-03-25 19:00頃
**元TODO**: `todo/20260325_1810_plan_web_dashboard_PLAN_done.md`

## 作業の概要

WEBダッシュボード（検索ダッシュボード＋詳細ダッシュボード）の詳細開発計画を5フェーズに分割して作成した。

## 考えたこと・作業内容

### 現状分析

プロジェクトの現在の状態を調査した結果:

- **Web UI は完全に未実装**: コントローラー・ビュー・ルートは一切存在しない
- **Rails 8.1 + Hotwire スタック**: importmap-rails、Turbo、Stimulusが導入済みだが未使用
- **CSS フレームワーク未導入**: Tailwind/Bootstrap等なし。素のCSSのみ
- **チャートライブラリ未導入**: Chart.js等なし
- **バックエンドのQueryObject**: `SectorComparisonQuery`, `TechnicalScreeningQuery` の2つのみ実装済み。設計済みだが未実装のものが多数あり (`ScreeningQuery`, `FinancialTimelineQuery` 等 — `dev_analysis_query_layer` DEVELOP pending)
- **58+の指標**: `FinancialMetric` に包括的な指標が計算・保持されている
- **スクリーニングプリセット**: 設計計画のみ存在 (`plan_watchlist_screening_preset` PLAN pending)

### アーキテクチャ判断

1. **Hotwire (Turbo + Stimulus) ベース**: React/Vue等のSPAフレームワークは導入せず、Railsの標準スタックで構築する。理由:
   - Gemfileにすでにturbo-rails, stimulus-railsが含まれている
   - サーバーサイドレンダリングベースで構築しつつ、必要箇所だけJSで動的に
   - Turbo Frames/Streamsで十分にSPA的な体験が実現可能

2. **Chart.js**: importmap経由で導入。ESM対応、軽量、ダークモードカスタマイズ容易

3. **ダークモードデフォルト**: CSS Custom Propertiesベース。`data-theme` 属性切替

4. **検索条件のJSON仕様**: AND/ORのネスト可能な構造。SQLフィルタ（固定カラム）とRubyフィルタ（data_json内指標）のハイブリッド

5. **条件プリセット**: `screening_presets` テーブルで管理。ビルトイン/カスタムの2種類。他のプリセットを参照する `preset_ref` 条件タイプで組み合わせ利用に対応

### フェーズ分割の理由

5フェーズに分割した理由:
- Phase 1 (基盤) は他の全フェーズの前提
- Phase 2/3 (検索バックエンド/フロントエンド) は分離することで、バックエンドのテストを先に確立してからフロントエンドに着手できる
- Phase 4/5 (詳細バックエンド/フロントエンド) も同様
- 各フェーズが単独で意味のある成果物を持つ

### 依存関係への対処

`dev_analysis_query_layer` (20260312_1000) が未実装であり、`ScreeningQuery` と `FinancialTimelineQuery` がダッシュボードの前提として必要。各フェーズのTODOに「未完了の場合は最小実装を含める」と記載し、柔軟に対応できるようにした。

## 成果物

以下の5つのDEVELOP TODOファイルを作成:

1. `20260325_1810_dev_dashboard_phase1_foundation_DEVELOP_pending.md` — 基盤構築（CSS、レイアウト、Chart.js導入、ルーティング）
2. `20260325_1810_dev_dashboard_phase2_search_backend_DEVELOP_pending.md` — 検索バックエンド（ScreeningPresetモデル、条件JSONスキーマ、ConditionExecutor、コントローラー）
3. `20260325_1810_dev_dashboard_phase3_search_frontend_DEVELOP_pending.md` — 検索フロントエンド（フィルタビルダーUI、結果テーブル、プリセット保存）
4. `20260325_1810_dev_dashboard_phase4_detail_backend_DEVELOP_pending.md` — 詳細バックエンド（DashboardSummary、チャートデータJSON API）
5. `20260325_1810_dev_dashboard_phase5_detail_frontend_DEVELOP_pending.md` — 詳細フロントエンド（グラフ+テーブル並列表示、タブUI、比較ビュー）
