# WORKLOG: THINK - 運用基盤と分析品質のギャップ特定

**作業日時**: 2026-03-20 09:00

## 作業の概要

過去4回のTHINKセッション（2026-03-19 14:00〜17:00）で作成された25件のpending TODOを踏まえ、まだカバーされていない領域を特定し、5件の新規TODOを作成した。

## 分析のアプローチ

前回までのTHINKセッションが主に「分析指標の拡充」「データ品質」「UI/出力」に焦点を当てていたのに対し、今回は以下の3つの異なる観点から調査した。

### 1. バリュエーション追跡の時間解像度

現在のバリュエーション指標（PER/PBR/PSR）は決算日前後の株価1点でのみ算出されている。しかし、プロジェクト目標の「飛躍前の変化を調べる」には、バリュエーションの日次推移が不可欠。

- 時価総額はget_valuation_metricsとget_ev_ebitda内でインラインに計算されるのみで永続化されていない
- 日次PER/PBRの追跡テーブルは存在しない
- これは既存TODOのいずれにもカバーされていない独立した課題

### 2. 利益の質の定量評価

既存の指標は「成長性」「収益性」「CF状況」を個別に捉えているが、「利益が本物か（キャッシュに裏付けられているか）」を直接評価するアクルーアル分析が欠落している。

- operating_cfとnet_incomeは両方取得済みだが、その比率（現金転換率）は未算出
- アクルーアル比率は利益操作の検出や将来業績予測に有用とされる学術的に確立された指標
- dev_extend_financial_health_metricsは B/S由来の指標（流動比率等）に焦点を当てており、利益の質分析とは異なる軸

### 3. 運用基盤とテストインフラ

25件のpending TODOを効率的に消化していくための基盤に注目した。

- **Rakeタスクの不在**: 全ジョブの実行がRails console経由のみ。cron連携も煩雑
- **FactoryBotの不在**: テストデータの構築が手動。25件のDEVELOP TODOの多くがテストを要するため、ファクトリ基盤が先行実装されるべき
- **Jobスペックのカバレッジ**: 6ジョブ中1つ（import_edinet_documents_job）のみテスト済み。ただしテスティング規約では「モデルに切り出されたメソッドのテスト」が方針であり、現状のジョブはロジックがジョブ内に留まっているため、テスト追加よりもメソッド切り出しの検討が先行すべき

### 4. 決算期の正規化

複数の既存TODO（quarterly_yoy, cagr, sector_analysis, company_lifecycle）に横断的に影響する基盤的な問題として、決算期変更・変則決算への対応がどのTODOでも明示的に扱われていないことを発見した。

## 作成したTODO（5件）

| ファイル | TYPE | 内容 |
|---------|------|------|
| `20260320_0900_dev_daily_valuation_timeseries_DEVELOP_pending.md` | DEVELOP | 日次バリュエーション（PER/PBR/PSR/時価総額）の算出・蓄積。新テーブル `daily_valuations` と算出ジョブ |
| `20260320_0901_dev_earnings_quality_analysis_DEVELOP_pending.md` | DEVELOP | アクルーアル分析。現金転換率・アクルーアル比率・CF-利益乖離の算出。FinancialMetric.data_json拡張 |
| `20260320_0902_dev_rake_operations_tasks_DEVELOP_pending.md` | DEVELOP | sync/metrics/check/data系Rakeタスク群。日常運用のCLIインターフェース |
| `20260320_0903_improve_test_data_factories_DEVELOP_pending.md` | DEVELOP | FactoryBot導入と全モデルのファクトリ定義。テスト拡充の生産性基盤 |
| `20260320_0904_plan_fiscal_period_normalization_PLAN_pending.md` | PLAN | 決算期変更・変則決算・LTM算出・企業間比較の正規化フレームワーク設計 |

## 考えたこと

### 今回のTODO作成方針

過去4回のTHINKでは分析機能（メトリクス・スクリーニング・UI）が中心だったが、今回は「それらを効率的に実装・運用するための基盤」に着目した。

- **FactoryBotとRakeタスクは25件のpending TODO消化を加速させるインフラ**であり、早期に実装するほどROIが高い
- **日次バリュエーションは既存の分析の時間解像度を桁違いに向上させる**。特に「割安時に仕込む」という投資分析の核心的なニーズに直結する
- **アクルーアル分析は既存データから追加コストなく算出可能**であり、利益の信頼性という新たな分析軸を提供する
- **決算期正規化はPLANとした**。設計判断が必要な項目（変則決算のスキップ vs 年度換算、LTMの計算方式等）が多く、実装前に方針を固めるべき

### 既存TODOとの関係

- `dev_daily_valuation_timeseries` は `dev_stock_technical_indicators` と補完的（テクニカル=価格パターン、バリュエーション=ファンダメンタル評価）
- `dev_earnings_quality_analysis` は `dev_extend_financial_health_metrics`（B/S健全性指標）と `dev_composite_financial_scores`（統合スコア）の両方に入力を提供
- `plan_fiscal_period_normalization` は `dev_quarterly_yoy_comparison`, `dev_cagr_multiyear_growth_metrics`, `dev_sector_analysis_foundation`, `dev_company_lifecycle_tracking` の4つのTODOに横断的に影響する基盤設計

### 実装優先度の更新提案（30件のpending TODO全体）

前回のPhase分けを更新:

1. **Phase 0 (開発基盤)**: improve_test_data_factories → dev_rake_operations_tasks
2. **Phase 1 (分析基盤)**: dev_analysis_query_layer → improve_sqlite_query_performance → improve_import_fault_tolerance
3. **Phase 2 (設計)**: plan_fiscal_period_normalization → plan_screening_state_change_detection
4. **Phase 3 (指標拡充)**: dev_extend_financial_health_metrics → dev_earnings_quality_analysis → dev_dupont_roe_decomposition → dev_cagr_multiyear_growth_metrics → dev_operating_leverage_analysis → dev_quarterly_yoy_comparison → dev_dividend_payout_analysis
5. **Phase 4 (時系列・セクター)**: dev_daily_valuation_timeseries → dev_sector_analysis_foundation → dev_composite_financial_scores → dev_forecast_revision_tracking
6. **Phase 5 (データ品質)**: dev_cross_source_data_validation → improve_data_coverage_analysis → dev_company_lifecycle_tracking
7. **Phase 6 (インフラ)**: dev_job_scheduling → dev_job_monitoring_notification
8. **Phase 7 (出力)**: dev_data_export_cli → plan_web_api → plan_web_dashboard
9. **Phase 8 (高度分析)**: plan_trend_turning_point_detection → plan_screening_state_change_detection → dev_stock_technical_indicators → plan_historical_data_backfill → plan_edinet_xbrl_enrichment

### 見送った項目

- **ウォッチリスト/企業グループ管理**: 有用だがUI層の設計と密接に関連するため、plan_web_dashboard内で検討すべき
- **ジョブのメソッド切り出しとテスト追加**: 各DEVELOP TODOの実装時に自然と発生するため、独立TODOとしては不要
- **データのバージョニング/監査証跡**: オーバーエンジニアリングのリスク。現時点ではupsertで十分
