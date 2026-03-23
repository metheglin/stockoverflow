# WORKLOG: 分析深度・バリュエーション領域のギャップ分析

**作業日時**: 2026-03-20 15:00
**TODO_TYPE**: THINK
**作業者**: AI

## 作業概要

既存の35件のpending TODOとコードベース全体を精査し、カバーされていない分析領域を特定して5つの新規TODOを作成した。

## 分析アプローチ

### 既存TODOの体系的分類

既存pending TODOを以下のカテゴリに分類し、各カテゴリのカバー率を評価:

| カテゴリ | 既存TODO数 | カバー率 | 備考 |
|---------|-----------|---------|------|
| 成長性指標 | 3 | 高 | YoY, CAGR, 連続成長 |
| 収益性指標 | 3 | 高 | ROE分解, 営業レバレッジ, マージン |
| 財務健全性 | 2 | 中 | 流動比率/D-E比率あり、運転資本サイクルなし |
| CF分析 | 1 | 中 | 利益の質あり、CF構成分析なし |
| バリュエーション | 1 | 低 | 静的指標のみ、成長率調整なし |
| 株主還元 | 1 | 低 | 配当のみ、自社株買い分析なし |
| 予想精度 | 1 | 低 | 予想修正追跡あり、精度プロファイルなし |
| 四半期分析 | 1 | 低 | YoY比較のみ、季節性分析なし |
| セクター分析 | 1 | 高 | 包括的 |
| スコアリング | 2 | 高 | 複合スコア、Piotroski |
| データ品質 | 3 | 高 | 検証、カバレッジ、耐障害性 |
| インフラ | 5 | 高 | ジョブ管理、Rake、テスト工場、SQLite、エクスポート |
| 設計(PLAN) | 7 | 高 | API、UI、トレンド検出、スクリーニング等 |

### 特定されたギャップ

カバー率が「低」または「中」の領域に着目し、以下の5つを新規TODOとして策定:

## 作成したTODO（5件）

### 1. 運転資本サイクル（CCC）メトリクス（DEVELOP）

**ファイル**: `20260320_1500_dev_working_capital_cycle_metrics_DEVELOP_pending.md`

- EdinetXbrlParserの拡張: 売上債権（NotesAndAccountsReceivableTrade）、棚卸資産（Inventories）、仕入債務（NotesAndAccountsPayableTrade）の3要素を追加抽出
- FinancialMetric: 売上債権回転日数、棚卸資産回転日数、仕入債務回転日数、CCC（Cash Conversion Cycle）の4指標
- 既存の `dev_extend_financial_health_metrics` では総資産回転率止まり。運転資本の内訳は未カバー
- 既存の `plan_edinet_xbrl_enrichment` はセグメント情報・従業員・R&D・減価償却・有利子負債に焦点。売上債権/棚卸資産/仕入債務は対象外

**選定理由**: CCCはバフェットが重視する指標の一つ。事業効率の本質を表し、飛躍前兆の検出（CCCが短縮傾向の企業）にも有用。

### 2. 経営者予想精度プロファイル（DEVELOP）

**ファイル**: `20260320_1501_dev_management_forecast_accuracy_profile_DEVELOP_pending.md`

- 既存surprise_metricsの複数期集計による企業固有の予想精度特性の定量化
- bias（conservative/optimistic/neutral）、consistency（high/medium/low）、beat_rate
- 既存の `dev_forecast_revision_tracking` は期中の修正履歴追跡で、「精度プロファイル」とは観点が異なる

**選定理由**: 保守的な業績予想を一貫して出す企業を特定できれば、次期予想発表時に「実力値はもっと上」という投資判断の根拠になる。

### 3. 四半期売上季節性分析（DEVELOP）

**ファイル**: `20260320_1502_dev_quarterly_revenue_seasonality_analysis_DEVELOP_pending.md`

- 同一年度内のQ1:Q2:Q3:Q4構成比パターンの分析
- 偏り指標（正規化ハーフィンダール指数）、Q4偏重度、季節性安定度
- 既存の `dev_quarterly_yoy_comparison` は前年同期比（Q1 vs Q1）で、年度内の構成比は未カバー

**選定理由**: Q4偏重企業の利益の質に対する懸念を定量化。ストック型ビジネス（均等配分）の検出にも有用。

### 4. 株主還元・自社株買い分析（DEVELOP）

**ファイル**: `20260320_1503_dev_shareholder_return_buyback_analysis_DEVELOP_pending.md`

- TSR（株主総利回り）、自社株買い利回り、総還元性向、自己株式比率、発行済株式数変化率
- 既存の `dev_dividend_payout_analysis` は配当固有の指標のみ。自社株買いによる還元は未カバー
- treasury_shares, shares_outstanding は FinancialValue に格納済み

**選定理由**: 日本企業の自社株買いは近年急増。配当のみの分析では株主還元の全体像を把握できない。

### 5. PEGレシオ・成長性調整バリュエーション（DEVELOP）

**ファイル**: `20260320_1504_dev_peg_ratio_growth_adjusted_valuation_DEVELOP_pending.md`

- PEG（PER/EPS成長率）、売上高成長率ベースPEG、EV/EBITDA to Growth、PBR/ROE比率、growth_value_gap
- 既存のバリュエーション指標（PER/PBR/PSR/EV-EBITDA）は静的な指標のみ。成長率を考慮した割安度評価は未カバー
- 複合スコアリングTODO（`dev_composite_financial_scores`）はPercentileランクベースであり、PEG等の直接的な成長率調整とは異なる

**選定理由**: GARP（Growth at a Reasonable Price）投資は最も実践的な投資スタイルの一つ。PER=30が割高かどうかは成長率次第であり、PEGはこの判断を直接可能にする。

## 考えたこと

### 既存TODOとの重複回避

各TODOの策定にあたり、既存の全pending TODO（35件）の内容を精査し、以下の観点で重複がないことを確認した:

- 同一の指標を算出していないか
- 同一のデータソースを拡張していないか
- 既存TODOの「将来の拡張」として言及されていないか

### 実装優先度の考察

新規5件のTODOの推奨実装順序:

1. **PEGレシオ**（依存なし、既存PER/YoYの値を組み合わせるだけで即実装可能）
2. **株主還元分析**（treasury_shares/shares_outstanding は既に格納済み）
3. **経営者予想精度プロファイル**（surprise_metricsデータの蓄積量に依存）
4. **運転資本サイクル**（XBRLパーサー拡張が必要）
5. **四半期季節性分析**（四半期データの蓄積状況に依存）

### プロジェクト全体の俯瞰

pending TODOは40件に達した。実装フェーズにおいては、以下の基盤TODOの優先完了が全体の生産性を大きく左右する:

- `improve_test_data_factories` - テスト実行のボトルネック解消
- `dev_rake_operations_tasks` - データ投入・再計算の運用効率化
- `dev_analysis_query_layer` - スクリーニング機能の基盤

これら基盤TODOの完了後に、本THINKで作成した分析メトリクス系TODOに着手するのが効率的。
