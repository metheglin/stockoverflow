# DEVELOP: Company検索・ルックアップメソッドの追加

## 概要

Companyモデルに、名前・証券コード・セクター・市場区分などによる柔軟な検索・ルックアップ機能を追加する。

## 背景・動機

現在、Companyモデルには `listed` スコープと `get_attributes_from_jquants` クラスメソッドのみが定義されている。実際の分析作業では:

- 「トヨタ」で企業を検索したい → `Company.where("name LIKE ?", "%トヨタ%")` を毎回手書きする必要がある
- セクター別の企業一覧がほしい → 17業種/33業種コードを覚えている必要がある
- 特定の市場区分の企業を絞りたい → `market_code` の値を知っている必要がある
- データが充実している企業から優先的に分析したい → 手段がない

Rakeタスク（TODO: dev_rake_operations_tasks）や対話的分析コンソール、Web API（TODO: plan_web_api）の全てで企業検索は基本操作であり、モデル層に共通メソッドとして用意しておくことで各機能の実装が効率化される。

## 実装方針

### スコープの追加

プロジェクトのユースケースにとって重要なクエリをスコープとして定義する（rails.mdの方針に準拠）:

```ruby
class Company < ApplicationRecord
  # 既存
  scope :listed, -> { where(listed: true) }

  # 追加: データの充実度が高い企業（financial_values を持つ上場企業）
  scope :with_financial_data, -> {
    listed.where(id: FinancialValue.select(:company_id).distinct)
  }
end
```

### クラスメソッドの追加

```ruby
class Company < ApplicationRecord
  class << self
    # 名前（日本語/英語）による部分一致検索
    # keyword: 検索キーワード
    # 戻り値: ActiveRecord::Relation
    def search_by_name(keyword)
      where("name LIKE :q OR name_english LIKE :q", q: "%#{sanitize_sql_like(keyword)}%")
    end

    # 証券コードによる検索（前方一致。4桁でも5桁でも対応）
    def search_by_code(code)
      where("securities_code LIKE ?", "#{sanitize_sql_like(code)}%")
    end

    # セクターによる絞り込み
    # sector_code: sector17_code または sector33_code
    def search_by_sector(sector_code)
      where(sector17_code: sector_code)
        .or(where(sector33_code: sector_code))
    end

    # 市場区分による絞り込み
    def search_by_market(market_name)
      where(market_name: market_name)
    end

    # 汎用検索（証券コード or 名前で検索）
    # query: 数字で始まる場合はコード検索、それ以外は名前検索
    def lookup(query)
      if query.match?(/\A\d/)
        search_by_code(query)
      else
        search_by_name(query)
      end
    end
  end
end
```

### 便利メソッド

```ruby
class Company < ApplicationRecord
  # この企業のFinancialValueの件数を返す
  def financial_data_count
    financial_values.count
  end

  # 直近の年次FinancialValueを返す
  def latest_annual_value(scope_type: :consolidated)
    financial_values
      .where(scope: scope_type, period_type: :annual)
      .order(fiscal_year_end: :desc)
      .first
  end

  # 直近の年次FinancialMetricを返す
  def latest_annual_metric(scope_type: :consolidated)
    financial_metrics
      .where(scope: scope_type, period_type: :annual)
      .order(fiscal_year_end: :desc)
      .first
  end
end
```

## テスト

- `spec/models/company_spec.rb` に追加
- テストケース:
  - `search_by_name`: 日本語名・英語名での部分一致検索
  - `search_by_code`: 4桁・5桁コードでの検索
  - `lookup`: 数字入力時のコード検索、文字列入力時の名前検索
  - `search_by_sector`: セクターコードによる絞り込み
  - `latest_annual_value`: 直近の年次データが返ること
- なるべくDB操作を最小限にしつつ、検索メソッドの正確性を検証

## 依存関係

- 既存のCompanyモデルに依存
- Rakeタスク系TODO（dev_rake_operations_tasks, dev_rake_task_pipeline_operations）の実装を効率化
- Web API（plan_web_api）のエンドポイント実装の基盤
- 企業インテリジェンスレポート（dev_company_intelligence_report_generator）の基盤
