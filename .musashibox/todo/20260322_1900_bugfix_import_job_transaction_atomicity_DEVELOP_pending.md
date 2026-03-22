# DEVELOP: インポートジョブのトランザクション原子性の確保

## 概要

ImportEdinetDocumentsJob および ImportJquantsFinancialDataJob において、FinancialReport と FinancialValue の作成が単一トランザクションで囲まれていないため、途中で例外が発生するとデータの不整合（孤立レコード）が生じる。各ドキュメント/ステートメントの処理をトランザクションで保護する。

## 背景・動機

### 現状の問題

**ImportEdinetDocumentsJob#process_document:**
1. `create_financial_report` で FinancialReport を作成（L128）
2. `upsert_financial_value` で FinancialValue を作成（L132-146）
3. 2の処理でバリデーションエラーや例外が発生すると、1で作成された FinancialReport が孤立する
4. rescue ブロックでエラーをキャッチしてログ出力するが、レポートのロールバックは行われない

**ImportJquantsFinancialDataJob#import_statement:**
1. `report.save!` で FinancialReport を永続化（L109）
2. `import_financial_value` で連結・個別の FinancialValue を作成（L112-127）
3. 連結の作成は成功したが個別の作成で例外発生した場合、連結のみ存在する中途半端な状態になる

### 影響

- 孤立した FinancialReport レコードの蓄積（FinancialValue を持たない報告書）
- DataIntegrityCheckJob がこの孤立レコードを検出しないため、問題が潜伏する
- 部分的にインポートされたデータが指標計算に影響を与える可能性

## 実装方針

### ImportEdinetDocumentsJob

```ruby
def process_document(doc)
  # ...前処理...

  ActiveRecord::Base.transaction do
    report = create_financial_report(doc, company: company, report_type: report_type)

    if xbrl_result[:consolidated]
      upsert_financial_value(...)
    end
    if xbrl_result[:non_consolidated]
      upsert_financial_value(...)
    end
  end

  @stats[:processed] += 1
rescue => e
  @stats[:errors] += 1
  Rails.logger.error(...)
end
```

### ImportJquantsFinancialDataJob

```ruby
def import_statement(data, company: nil)
  # ...前処理...

  ActiveRecord::Base.transaction do
    report.save! if report.new_record? || report.changed?
    import_financial_value(data, ..., scope_type: :consolidated)
    if has_non_consolidated_data?(data)
      import_financial_value(data, ..., scope_type: :non_consolidated)
    end
  end

  @stats[:imported] += 1
rescue => e
  # ...エラーハンドリング...
end
```

## 優先度

高。データ整合性に直結する基本的な保護が欠けている。
