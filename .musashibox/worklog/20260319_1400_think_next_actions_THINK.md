# WORKLOG: THINK - 次に取り組むべきアクションの検討

**作業日時**: 2026-03-19 14:00

**元TODO**: (THINK指示 - 直接のTODOファイルなし)

---

## 作業概要

プロジェクト全体の現状を精査し、既存の5つのpending TODOでカバーされていない領域を特定し、新たな4つのTODOを作成した。

## 現状分析

### 完成済みの基盤 (インフラ層: 95%完了)

- DBスキーマ: companies, financial_reports, financial_values, financial_metrics, daily_quotes, application_properties
- APIクライアント: EdinetApi, JquantsApi, EdinetXbrlParser
- インポートジョブ5本 + データ整合性チェックジョブ1本
- FinancialMetric: 成長性(YoY), 収益性(ROE/ROA/マージン), CF分析, バリュエーション(PER/PBR/PSR), Earning Surprise
- テストカバレッジ: FinancialMetric全クラスメソッドのテスト済み

### 既存pending TODO (5件)

| TODO | TYPE | 依存関係 |
|------|------|----------|
| dev_analysis_query_layer | DEVELOP | なし (最優先) |
| dev_job_scheduling | DEVELOP | なし (独立) |
| plan_web_api | PLAN | analysis_query_layer に依存 |
| dev_data_export_cli | DEVELOP | analysis_query_layer に依存 |
| dev_sector_analysis_foundation | DEVELOP | なし (独立) |

### 依存関係の整理

```
dev_analysis_query_layer ─┬─> dev_data_export_cli
                          └─> plan_web_api ──> plan_web_dashboard (NEW)

dev_job_scheduling ──> dev_job_monitoring_notification (NEW)

dev_sector_analysis_foundation ──> plan_trend_turning_point_detection (NEW)

dev_analysis_query_layer ──> dev_extend_financial_health_metrics (NEW)
```

## 考えたこと

### 指標カバレッジの不足

FinancialValueのdata_jsonにはEDINET XBRLから取得した `current_assets`, `current_liabilities`, `noncurrent_liabilities`, `shareholders_equity`, `cost_of_sales`, `gross_profit`, `sga_expenses` が格納されているが、これらを活用した指標（流動比率、負債資本倍率、総資産回転率、売上総利益率、販管費率）がFinancialMetricに存在しない。プロジェクトの「あらゆる指標を分析の対象として」という方針に対してギャップがある。

### トレンド転換の自動検出

ユースケース3（飛躍の直前の変化を調べる）は FinancialTimelineQuery で時系列を取れば手動分析は可能だが、約4,000社のデータから「今まさに転換が起きている企業」を自動的にスクリーニングする仕組みがない。これは転換パターンの定義設計が必要なため PLAN とした。

### UIの不在

Turbo/Stimulus/Propshaftが導入済みだがフロントエンドは皆無。REST API設計(plan_web_api)は計画されているがUI設計は未着手。API設計の後にUIを設計するのが自然な流れ。

### 運用監視の欠如

ジョブスケジューリングが実装されれば日次自動実行が始まるが、失敗検知の仕組みがない。DataIntegrityCheckJobの結果もapplication_propertiesに保存されるだけで通知されない。job_scheduling実装後に着手すべき運用上の必須項目。

## 作成したTODO (4件)

1. **dev_extend_financial_health_metrics** (DEVELOP, pending)
   - 流動比率・負債資本倍率・総資産回転率・売上総利益率・販管費率の算出
   - 既存XBRL data_jsonデータを活用、FinancialMetric + CalculateFinancialMetricsJob を拡張

2. **plan_trend_turning_point_detection** (PLAN, pending)
   - 増収増益開始・利益率底打ち・FCF黒字転換・ROE反転等のパターン定義設計
   - データモデルの設計方針（data_json拡張 vs 専用テーブル vs EAV）

3. **plan_web_dashboard** (PLAN, pending)
   - ダッシュボード・企業一覧・企業詳細・セクター画面の設計
   - Turbo+Stimulus+Chart.jsによる技術スタック設計

4. **dev_job_monitoring_notification** (DEVELOP, pending)
   - JobMonitorableモジュールによる実行結果記録
   - /health/jobs エンドポイントによる外部監視対応

## 推奨実装順序

1. `dev_analysis_query_layer` + `dev_job_scheduling` (既存、並行可能)
2. `dev_extend_financial_health_metrics` + `dev_sector_analysis_foundation` (既存、並行可能)
3. `dev_job_monitoring_notification` + `dev_data_export_cli` (並行可能)
4. `plan_web_api` → `plan_web_dashboard`
5. `plan_trend_turning_point_detection` (セクター分析基盤完了後)
