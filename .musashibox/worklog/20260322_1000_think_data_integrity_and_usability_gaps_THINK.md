# THINK: データ整合性と利用可能性のギャップ分析

**作業日時**: 2026-03-22 10:00

## 作業概要

プロジェクト全体の現状を分析し、既存110+件のpending TODOではカバーされていない重要なギャップを特定した。
特に「データの正確性・追跡可能性」と「分析基盤のユーザビリティ」の2軸に着目した。

## 分析のアプローチ

### 前提: 既存THINKセッションとの差別化

これまでの14回のTHINKセッションは主に以下の領域をカバーしている:
- 財務指標の拡充（25+ DEVELOP TODO）
- データ品質・バリデーション（8 DEVELOP TODO）
- スクリーニング・分析（8 DEVELOP TODO）
- 運用インフラ（デプロイ、スケジューリング、モニタリング）
- 高度な分析（DCF、Piotroski、Altman、DuPont等）

### 今回の着眼点

既存TODOが「何を計算するか」に偏重している一方で、以下の基盤的問題が未検討だった:

1. **データソース間の単位整合性**: 計算の前提条件
2. **データのトレーサビリティ**: 問題発生時の影響範囲特定
3. **時系列データの取得容易性**: 全ての推移分析の共通基盤
4. **長期運用のデータ量見通し**: 100+機能を載せるインフラの妥当性
5. **企業のライフイベント追跡**: 歴史的分析の精度

## コードレビューで発見した具体的リスク

### 1. XBRL単位スケール問題

`EdinetXbrlParser#parse_numeric` (L243-250):
```ruby
def parse_numeric(text)
  cleaned = text.gsub(",", "")
  Integer(cleaned)
rescue ArgumentError
  Float(cleaned).to_i rescue nil
end
```

- `decimals`属性を無視している
- XBRL仕様では `decimals="-6"` は百万円単位を意味する
- JQUANTSが円単位で提供している場合、同一企業の同一期間で6桁の差が生じる可能性
- 全てのYoY計算、バリュエーション指標が破綻するリスク

### 2. 上場ステータスの情報欠落

`SyncCompaniesJob`は `listed` booleanをフリップするのみ:
- いつ上場廃止になったか不明
- 再上場のケースで履歴が残らない
- ユースケース3（飛躍直前の変化分析）で上場期間が不明

### 3. メトリクス時系列取得の不在

FinancialMetricモデルに時系列取得ヘルパーがない:
- 「ROEの5年推移」を取得するには毎回SQLを手組み
- `dev_financial_value_period_navigation` はFinancialValue（生データ）対象であり、FinancialMetric（算出指標）とは別レイヤー

### 4. FinancialValueのソース追跡不在

ImportEdinetDocumentsJobがdata_jsonを補完する際:
- どのフィールドがEDINET由来かJQUANTS由来か追跡されない
- XBRLパーサーのバグ修正後に影響範囲を特定できない
- `dev_cross_source_data_validation` の前提条件として必要

## 作成したTODO一覧

| ファイル名 | TODO_TYPE | 概要 |
|-----------|-----------|------|
| `20260322_1000_dev_xbrl_unit_scale_verification_DEVELOP_pending.md` | DEVELOP | XBRL単位・スケール検証と補正 |
| `20260322_1001_dev_company_listing_status_history_DEVELOP_pending.md` | DEVELOP | 企業の上場ステータス履歴管理 |
| `20260322_1002_dev_metric_time_series_accessor_DEVELOP_pending.md` | DEVELOP | 指標タイムシリーズアクセサの実装 |
| `20260322_1003_plan_data_volume_growth_and_retention_PLAN_pending.md` | PLAN | データ量増加予測とリテンション戦略 |
| `20260322_1004_dev_financial_value_source_field_tracking_DEVELOP_pending.md` | DEVELOP | フィールド別データソース追跡 |

## 所感

プロジェクトは「何を計算するか」のTODOが充実している一方、「計算の前提条件は正しいか」「問題が起きたときに対処できるか」という守りの観点が手薄だった。
特にXBRL単位問題は、発見が遅れると全ての指標データの再計算が必要になるため、分析機能の拡充より優先して検証すべきと考える。
