# WORKLOG: WEBダッシュボードの優先タスク確認

**作業日時**: 2026-03-27
**元TODO**: `todo/20260326_2002_plan_web_dashboard_priority_PLAN_inprogress.md`

## 作業の概要

pendingタスク約100件を確認し、WEBダッシュボード拡充のために優先すべきタスクを洗い出した。3フェーズの開発計画（Phase 6/7/8）として新たなDEVELOP TODOを作成した。

## 現状分析

### ダッシュボードの完了状況（Phase 1-5）

| Phase | 内容 | 状態 |
|-------|------|------|
| Phase 1 | 基盤構築（CSS, レイアウト, Chart.js, ルーティング） | 完了 |
| Phase 2 | 検索バックエンド（ScreeningPreset, ConditionExecutor） | 完了 |
| Phase 3 | 検索フロントエンド（フィルタビルダー, 結果テーブル） | 完了 |
| Phase 4 | 詳細バックエンド（DashboardSummary, チャートAPI） | 完了 |
| Phase 5 | 詳細フロントエンド（4タブ, 比較ビュー） | 完了 |

### 既に実装済みの機能

- 企業一覧・検索（デバウンス付きインクリメンタル検索）
- 企業詳細（財務データ/指標推移/株価/比較の4タブ）
- Chart.js 7チャートタイプ（売上利益、成長率、収益性、CF、バリュエーション、1株指標、株価）
- 高度な検索（4条件タイプ: metric_range, data_json_range, metric_boolean, company_attribute）
- AND/OR ネスト、プリセット参照
- ビルトインプリセット6つ（連続増収増益、高ROE低PBR、高成長グロース、FCFプラス転換、高配当、総合スコアTOP100）
- ダーク/ライトテーマ切替
- セクター内ポジション（4分位表示）

### ダッシュボードの主な不足点

1. **データの深み**: 表示データは既存のYoY・スコアに限定。「方向性（改善/悪化）」「勢い（加速/減速）」の定量データがない
2. **時間軸スクリーニング**: 最新期のpoint-in-time条件のみ。「5年中4年以上ROE > 10%」のような時間軸条件が不可能
3. **イベント/変化の可視化**: 「何が変わったか」を即座に把握するイベントフィードがない
4. **転換点分析**: プロジェクトの主要ユースケース「業績飛躍の直前の変化」に対応する機能がない
5. **パーセンタイル**: セクターポジションが4分位の近似表示にとどまる

## 既存pendingタスクの分析

### ダッシュボードに直接関連するタスク（約20件精査）

#### Tier 1: 即座にダッシュボード表示を豊かにするもの
| タスク | 概要 | 複雑度 | 影響度 |
|--------|------|--------|--------|
| `dev_growth_acceleration_metrics` | 成長加速度（YoYの差分=2階微分） | 低 | 高 |
| `dev_metric_trend_classification` | トレンド分類ラベル（improving/turning_up等） | 中 | 高 |

#### Tier 2: スクリーニング能力を飛躍的に強化するもの
| タスク | 概要 | 複雑度 | 影響度 |
|--------|------|--------|--------|
| `dev_multi_period_screening_conditions` | 時間軸をまたぐスクリーニング条件 | 中-高 | 非常に高 |

#### Tier 3: 分析の深みを加えるもの
| タスク | 概要 | 複雑度 | 影響度 |
|--------|------|--------|--------|
| `dev_financial_event_detection` | 財務イベントの自動検出・記録 | 中 | 高 |
| `dev_trend_turning_point_detection` | 6パターンの転換点検出 | 高 | 高 |
| `dev_metric_percentile_ranking` | パーセンタイル順位算出 | 中 | 中 |

#### Tier 4: パフォーマンス・インフラ
| タスク | 概要 | 複雑度 | 影響度 |
|--------|------|--------|--------|
| `dev_company_latest_snapshot_cache` | スクリーニング高速化キャッシュ | 中 | 中（データ量増加時に重要） |

### 既に実質完了しているpendingタスク

以下のタスクはダッシュボード開発の過程で実質的に完了済み。pendingのままだが、別途対応が必要:

- `plan_watchlist_screening_preset` → ScreeningPresetモデル・CRUD・プリセット管理は実装済み
- `dev_company_financial_timeline_view` → Company::FinancialTimelineQuery が実装済み
- `dev_analysis_query_layer` → latest_periodスコープ実装済み、ConditionExecutorがScreeningQueryの上位互換。ただしConsecutiveGrowthQuery、CashFlowTurnaroundQueryは未実装

### ダッシュボード拡充には直接関連しないpendingタスク

以下は価値があるが、WEBダッシュボード拡充の文脈では優先度が低い:

- `dev_screening_result_table_formatter` — CLI/コンソール向け
- `dev_model_summary_display_methods` — CLI/コンソール向け
- `dev_data_export_cli` — CLI向けエクスポート
- `dev_job_monitoring_notification` — バックエンドインフラ
- `dev_import_progress_tracking` — バックエンドインフラ
- `plan_operational_health_dashboard` — 運用ダッシュボード（ユーザー分析ダッシュボードとは別）

## 優先順位の判断根拠

### Phase 6（データエンリッチメント）を最優先とした理由

1. **低コスト・高リターン**: data_jsonへのフィールド追加は既存のインフラ（CalculateFinancialMetricsJob）に乗るため、新テーブル不要
2. **即座に見える効果**: ダッシュボードのサマリーカードにトレンドバッジが表示されるようになり、UI改善が分かりやすい
3. **後続フェーズの基盤**: トレンドラベルと加速度データは、Phase 7の時間軸スクリーニングやPhase 8のイベント検出で利用できる

### Phase 7（高度なスクリーニング）を2番目とした理由

1. **プロジェクトの核心ユースケースに直結**: 「6期連続増収増益」以外の時間軸条件（ROEの安定性、利益率の連続改善等）が使えるようになる
2. **既存の検索UIを大幅に強化**: フィルタビルダーに新しい条件タイプを追加するだけで既存UIが進化する
3. **Phase 6のデータに依存しない**: 独立して実装可能だが、Phase 6で追加されたトレンドラベルを条件に使えるとさらに有用

### Phase 8（イベント・転換点）を3番目とした理由

1. **最も複雑**: 2つの新テーブル（financial_events, trend_turning_points）と新ジョブが必要
2. **Phase 6のデータを活用**: トレンド分類・加速度データがあると転換点検出の精度が向上
3. **単独でも価値がある**: イベントフィードだけでも企業詳細の情報密度を大幅に向上させる

## 成果物

3つのDEVELOP TODOファイルを作成:

1. `20260326_2002_dev_dashboard_phase6_data_enrichment_DEVELOP_pending.md`
   - 成長加速度メトリクス + トレンド分類 + ダッシュボードUI統合
2. `20260326_2002_dev_dashboard_phase7_advanced_screening_DEVELOP_pending.md`
   - MultiPeriodConditionEvaluator + フィルタビルダー時間軸条件UI
3. `20260326_2002_dev_dashboard_phase8_event_analysis_DEVELOP_pending.md`
   - 財務イベント検出 + トレンド転換点検出 + パーセンタイルランキング + ダッシュボードUI統合
