# DEVELOP: 孤立FinancialReport検出をDataIntegrityCheckJobに追加

## 概要

FinancialValue を持たない孤立した FinancialReport レコードを DataIntegrityCheckJob で検出する整合性チェックを追加する。

## 背景・動機

### 現状の問題

DataIntegrityCheckJob は4つのチェックを実行する:
1. missing_metrics: FinancialValue に対応する FinancialMetric がないケース
2. missing_daily_quotes: 上場企業に直近の株価がないケース
3. consecutive_growth_integrity: 連続増収増益カウンターの整合性
4. sync_freshness: 同期日時の鮮度

しかし **「FinancialReport が存在するが FinancialValue が1件も紐づかない」** ケースを検出していない。

### 孤立レポートの発生原因

1. **XBRL解析成功後のインポート失敗**: ImportEdinetDocumentsJob で create_financial_report 成功後に upsert_financial_value で例外発生（トランザクション未使用のため）
2. **JQUANTSインポートの部分失敗**: import_statement で report.save! 成功後に import_financial_value で例外発生
3. **XBRL解析の空結果**: パーサーが構造を返すが実際の財務数値が空のケース

### 影響

- FinancialReport.count による統計が実態より多くなる
- source_counts（EDINET/JQUANTS別のレポート数）も過大計上
- generate_summary の data_counts.financial_values_total との乖離が見えにくい
- 孤立レポートの蓄積によるDBサイズの不要な増大

## 実装方針

DataIntegrityCheckJob に `check_orphaned_reports` メソッドを追加:

```ruby
def check_orphaned_reports
  orphaned = FinancialReport
    .left_joins(:financial_value)
    .where(financial_values: { id: nil })

  orphaned_count = orphaned.count
  sample_doc_ids = orphaned.limit(10).pluck(:doc_id)
  source_breakdown = orphaned.group(:source).count

  @summary[:orphaned_reports] = {
    orphaned_count: orphaned_count,
    total_reports: FinancialReport.count,
    by_source: source_breakdown,
  }

  if orphaned_count > 0
    add_issue(
      check: "orphaned_reports",
      severity: orphaned_count > 100 ? "error" : "warning",
      message: "#{orphaned_count}件のFinancialReportにFinancialValueが紐づいていない",
      details: {
        orphaned_count: orphaned_count,
        sample_doc_ids: sample_doc_ids,
        by_source: source_breakdown,
      },
    )
  end
end
```

### perform メソッドへの追加

```ruby
def perform
  @issues = []
  @summary = {}

  check_missing_metrics
  check_missing_daily_quotes
  check_orphaned_reports        # 追加
  check_consecutive_growth_integrity
  check_sync_freshness
  generate_summary

  save_results
  log_results
end
```

### FinancialReport モデルの関連確認

現在 FinancialReport は `has_one :financial_value` を持つが、実際にはスコープ別（consolidated/non_consolidated）で複数の FinancialValue が紐づく可能性がある。`has_many :financial_values` への変更も検討する。ただし既存コードへの影響を確認すること。

## 優先度

中。データ整合性の可視化に貢献する。特に bugfix_import_job_transaction_atomicity（20260322_1900）の修正前に検出機構を先に入れておくことで、現状の孤立レポート数を把握できる。
