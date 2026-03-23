# THINK: 未カバー領域の特定と新規TODO作成

**作業日時**: 2026-03-19 16:00

## 作業概要

プロジェクト全体のコードベースと既存TODO（14件pending、9件done）を精査し、既存TODOでカバーされていない重要な機能的・技術的ギャップを特定。6件の新規TODOを作成した。

## 分析プロセス

### 現状の確認

- **データパイプライン**: 企業マスタ同期、JQUANTS/EDINET財務データ取込、日次株価取込、指標計算、データ整合性チェック — すべて実装済み
- **指標計算**: 成長性(YoY)、収益性(ROE/ROA/利益率)、CF分析、連続成長追跡、バリュエーション(PER/PBR等)、EV/EBITDA、決算サプライズ — すべて実装済み
- **既存pending TODO**: セクター分析、分析クエリ層、データエクスポート、ジョブスケジューリング、予想修正追跡、テクニカル指標、ジョブ監視、データカバレッジ分析、財務健全性指標追加、Web API設計、XBRL拡張、トレンド転換検出、過去データバックフィル、Webダッシュボード

### 特定したギャップ

プロジェクト目標の3つのユースケースと「あらゆる指標を分析の対象として履歴を保持し、推移やトレンドの転換がわかるようにしたい」という要件に照らし合わせ、以下の未カバー領域を特定:

1. **四半期前年同期比の不在** — 四半期データに対する季節性を考慮した比較ロジックが明示的に設計されていない
2. **複合スコアリングの不在** — 個別指標は豊富だが、統合ランキングの仕組みがない。「注目すべき企業を一覧」の直接的な解決策
3. **状態変化検出の不在** — 静的スクリーニングは計画中だが、「新たに条件を満たした企業」の動的検出がない
4. **クロスソースバリデーションの不在** — EDINET/JQUANTS双方のデータ整合性確認がない
5. **配当分析の不足** — dividend_yieldのみ。配当性向・連続増配は未実装
6. **SQLite性能最適化の未検討** — データ量増加に備えた設定・インデックス戦略が未整備

### 作成したTODO

| ファイル | TODO_TYPE | 内容 |
|---|---|---|
| `20260319_1600_dev_quarterly_yoy_comparison_DEVELOP_pending.md` | DEVELOP | 四半期前年同期比メトリクス |
| `20260319_1601_dev_composite_financial_scores_DEVELOP_pending.md` | DEVELOP | 複合財務スコアリング |
| `20260319_1602_plan_screening_state_change_detection_PLAN_pending.md` | PLAN | スクリーニング状態変化検出設計 |
| `20260319_1603_dev_cross_source_data_validation_DEVELOP_pending.md` | DEVELOP | EDINET/JQUANTSクロスバリデーション |
| `20260319_1604_dev_dividend_payout_analysis_DEVELOP_pending.md` | DEVELOP | 配当分析メトリクス |
| `20260319_1605_improve_sqlite_query_performance_DEVELOP_pending.md` | DEVELOP | SQLiteクエリ性能最適化 |

## 考えたこと

- 既存のpendingが14件あるなか、重複しない領域に絞った。特にdev_analysis_query_layerやplan_trend_turning_point_detectionとの差分を意識した
- 複合スコアリングは既存TODOのどれともかぶらず、プロジェクト目標への直接的な貢献度が高い
- 状態変化検出は、plan_trend_turning_point_detection（トレンド転換の検出・可視化）とは異なり、「スクリーニング条件の達成/脱落」という運用的な観点
- SQLite性能は機能的ではないが、分析クエリ層やスクリーニング実装前に検討しておくべきインフラ課題
- 四半期YoYと配当分析はFinancialMetricの指標拡充として、既存のdev_extend_financial_health_metricsとは異なる軸（前者は四半期特化、後者はB/S由来の健全性指標）
