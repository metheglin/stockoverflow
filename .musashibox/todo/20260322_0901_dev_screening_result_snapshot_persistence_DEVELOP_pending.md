# dev_screening_result_snapshot_persistence

## 概要

スクリーニング結果のスナップショットを保存し、経時的な比較・追跡を可能にする機能を実装する。

## 背景・目的

本プロジェクトの3つのユースケースはいずれも「条件に合致する企業を見つける」ことが核だが、日々データが更新される中で**いつ条件に合致し始めたか、いつ外れたか**を追跡する仕組みがない。

例:
- 「先週の6期連続増収増益スクリーニングでは50社がヒットしたが、今週は48社。外れた2社はどこか？」
- 「企業Xがこのスクリーニングに初めて現れたのはいつか？」
- 「3ヶ月前のスクリーニング結果と現在を比較し、新たに加わった企業を特定する」

投資判断の振り返りや、スクリーニング条件自体の有効性評価に不可欠。

既存の関連TODO:
- `watchlist_screening_preset` は「スクリーニング条件の保存」→ 条件の保存であり結果の保存ではない
- `investor_alert_digest` は「通知の設計」→ 通知フォーマットの設計であり結果の永続化ではない
- 本TODOは「**結果そのもの**の保存と経時比較」に焦点

## 実装内容

### データベース

新テーブル `screening_snapshots` を追加:

| カラム | 型 | 説明 |
|--------|-----|------|
| id | integer | PK |
| name | string | スクリーニング名（例: "6期連続増収増益"） |
| executed_on | date | 実行日 |
| conditions_json | json | 実行時の条件（再現性のため） |
| result_count | integer | ヒット件数 |
| data_json | json | 結果の詳細 |
| created_at | datetime | |

`data_json` スキーマ:
```json
{
  "company_ids": [1, 2, 3, ...],
  "top_results": [
    {"company_id": 1, "securities_code": "7203", "name": "トヨタ自動車", "sort_value": 15.2},
    ...
  ],
  "added_since_last": [{"company_id": 5, "name": "..."}],
  "removed_since_last": [{"company_id": 8, "name": "..."}]
}
```

### ScreeningSnapshot モデル

```ruby
class ScreeningSnapshot < ApplicationRecord
  include JsonAttribute

  define_json_attributes :data_json, schema: {
    company_ids: { type: :array },
    top_results: { type: :array },
    added_since_last: { type: :array },
    removed_since_last: { type: :array },
  }

  define_json_attributes :conditions_json, schema: {
    filter_type: { type: :string },
    parameters: { type: :object },
  }

  # 前回スナップショットとの差分を計算
  def get_diff_from_previous
    previous = self.class.where(name: name).where("executed_on < ?", executed_on).order(executed_on: :desc).first
    return nil unless previous
    {
      added: company_ids - previous.company_ids,
      removed: previous.company_ids - company_ids,
      retained: company_ids & previous.company_ids,
    }
  end

  # 特定企業がこのスクリーニングに初めて現れた日を返す
  def self.get_first_appearance(name:, company_id:)
    where(name: name).order(executed_on: :asc).find { |s| s.company_ids.include?(company_id) }&.executed_on
  end
end
```

### スナップショット実行Job

- analysis_query_layer のスクリーニング結果を受け取り、ScreeningSnapshot に保存
- 前回との差分を自動計算して data_json に格納

## テスト方針

- ScreeningSnapshot#get_diff_from_previous のテスト
- ScreeningSnapshot.get_first_appearance のテスト

## 依存関係

- `analysis_query_layer` の完成が前提（スクリーニング結果を生成するクエリが必要）
- `watchlist_screening_preset` との連携を想定（保存された条件を定期実行し、スナップショット化）

## 優先度

Phase 2。analysis_query_layer 完成後に実装可能。ただし、テーブル設計はPhase 0で先行して作成してもよい。
