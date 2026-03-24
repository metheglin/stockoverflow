# DEVELOP: EdinetXbrlParser jpcrp_cor 名前空間対応（R&D・設備投資・従業員数）

## 概要

EdinetXbrlParser に jpcrp_cor（企業内容等の開示に関するタクソノミ）名前空間のサポートを追加し、有価証券報告書の「主要な経営指標等の推移」「研究開発活動」等に記載されるデータを抽出する。

## 背景・動機

### 現状

EdinetXbrlParser は jppfs_cor（財務諸表本体）名前空間のみ対応している。しかし、有価証券報告書にはjpcrp_cor名前空間で記述される重要なデータが含まれる:

- **研究開発費**: 企業の成長投資を測る重要指標。R&D集約度（R&D / 売上高）はイノベーション企業のスクリーニングに不可欠
- **設備投資額**: 設備投資 / 減価償却費の比率で成長投資の姿勢を評価。設備投資が減価償却を上回る企業は拡大フェーズ
- **従業員数**: 1人あたり売上高・利益の算出、生産性分析に必要。従業員数の急増は事業拡大のシグナル
- **減価償却費（経営指標）**: C/F計算書内の値と照合可能。経営指標として開示される値はC/Fのものと異なる場合がある

### jpcrp_cor と jppfs_cor の違い

- `jppfs_cor`: 財務諸表本体（P/L, B/S, C/F）の要素。金額はXBRLで構造化されている
- `jpcrp_cor`: 企業情報の記述要素。「事業の状況」「経理の状況」等に記載。多くはテキストブロックだが、一部数値データが構造化されている

### 構造化データとして取得可能な要素

以下の要素はXBRLの数値要素として構造化されており、jppfs_corと同様のXPath検索で抽出可能:

- `NumberOfEmployees` - 連結従業員数
- `ResearchAndDevelopmentExpensesSGA` - 研究開発費（販管費）
- `CapitalExpendituresSummaryOfBusinessResults` - 設備投資額
- `DepreciationAndAmortizationSummaryOfBusinessResults` - 減価償却費

## 追加するXBRL要素一覧

| data_json キー | XBRL要素候補 | 名前空間 | コンテキスト | 説明 |
|---|---|---|---|---|
| `research_and_development` | ResearchAndDevelopmentExpensesSGA, ResearchAndDevelopmentExpensesDE | jpcrp_cor | duration | 研究開発費 |
| `capital_expenditure` | CapitalExpendituresSummaryOfBusinessResults | jpcrp_cor | duration | 設備投資額 |
| `depreciation_summary` | DepreciationAndAmortizationSummaryOfBusinessResults | jpcrp_cor | duration | 減価償却費（経営指標） |
| `number_of_employees` | NumberOfEmployees | jpcrp_cor | instant | 従業員数 |

## 実装内容

### 1. register_namespaces の拡張

```ruby
def register_namespaces(doc)
  # jppfs_cor（財務諸表）
  unless doc.namespaces.values.any? { |ns| ns.include?("jppfs_cor") }
    doc.root&.add_namespace("jppfs_cor", "http://disclosure.edinet-fsa.go.jp/taxonomy/jppfs/cor")
  end

  # jpcrp_cor（企業報告）
  unless doc.namespaces.values.any? { |ns| ns.include?("jpcrp_cor") }
    doc.root&.add_namespace("jpcrp_cor", "http://disclosure.edinet-fsa.go.jp/taxonomy/jpcrp/cor")
  end
end
```

### 2. EXTENDED_ELEMENT_MAPPING に jpcrp_cor 要素を追加

```ruby
EXTENDED_ELEMENT_MAPPING = {
  # ... 既存要素 ...

  # jpcrp_cor 要素
  research_and_development: {
    elements: ["ResearchAndDevelopmentExpensesSGA", "ResearchAndDevelopmentExpensesDE"],
    namespace: "jpcrp_cor",
  },
  capital_expenditure: {
    elements: ["CapitalExpendituresSummaryOfBusinessResults"],
    namespace: "jpcrp_cor",
  },
  depreciation_summary: {
    elements: ["DepreciationAndAmortizationSummaryOfBusinessResults"],
    namespace: "jpcrp_cor",
  },
  number_of_employees: {
    elements: ["NumberOfEmployees"],
    namespace: "jpcrp_cor",
  },
}.freeze
```

### 3. DURATION_KEYS / INSTANT_KEYS の更新

```ruby
DURATION_KEYS = %i[
  # ... 既存 ...
  research_and_development capital_expenditure depreciation_summary
].freeze

INSTANT_KEYS = %i[
  # ... 既存 ...
  number_of_employees
].freeze
```

### 4. FinancialValue の data_json スキーマ拡張

```ruby
define_json_attributes :data_json, schema: {
  # ... 既存スキーマ ...

  # jpcrp_cor 要素
  research_and_development: { type: :integer },
  capital_expenditure: { type: :integer },
  depreciation_summary: { type: :integer },
  number_of_employees: { type: :integer },
}
```

### 5. コンテキストパターンの確認

jpcrp_cor の要素は jppfs_cor と同じコンテキストIDパターンを使用する:
- `CurrentYearDuration` (連結・期間)
- `CurrentYearInstant` (連結・時点)
- `CurrentYearDuration_NonConsolidatedMember` (個別・期間)
- `CurrentYearInstant_NonConsolidatedMember` (個別・時点)

ただし、`NumberOfEmployees` は連結のみ開示される場合が多い。個別で取得できない場合はnilとなり、既存の仕組みで対応済み。

## テスト

### EdinetXbrlParser のテスト

- jpcrp_cor 名前空間が正しく登録されること
- 各追加要素が正しく抽出されること
- jpcrp_cor 要素が存在しないXBRL（古い書類等）でもエラーにならないこと
- 既存の jppfs_cor 要素の抽出に影響がないこと

### データ格納のテスト

- jpcrp_cor 要素が data_json に正しく格納されること
- 従業員数が整数として格納されること

## 可能になる分析指標（後続TODOで実装）

| 指標 | 算出式 | 用途 |
|---|---|---|
| R&D集約度 | research_and_development / net_sales | イノベーション企業のスクリーニング |
| 設備投資比率 | capital_expenditure / net_sales | 成長投資の姿勢 |
| 設備投資/償却倍率 | capital_expenditure / depreciation | 1.0超 = 拡大投資中 |
| 1人あたり売上高 | net_sales / number_of_employees | 生産性指標 |
| 1人あたり営業利益 | operating_income / number_of_employees | 従業員効率 |
| 従業員数YoY | (今期 - 前期) / 前期 | 人員拡大・縮小の検出 |

## 注意事項

- jpcrp_cor の要素は有価証券報告書（120/130）には含まれるが、四半期報告書（140/150）には含まれない場合がある
- 研究開発費は開示していない企業もある（非該当の場合はnil）
- 従業員数にはパート・臨時雇用者を含まないことが多い（含む場合は別要素 AverageNumberOfTempWorkers）
- 金融業では設備投資の概念が異なるため取得できない場合がある

## 優先度

中。R&D集約度と従業員生産性は差別化された分析指標となる。ただし jppfs_cor 要素拡張の後に実施するのが自然。

## 依存関係

- 先行: `dev_xbrl_jppfs_element_expansion`（jppfs_cor拡張を先に完了し、DURATION_KEYS/INSTANT_KEYSの拡張パターンを確認）
- 後続: `dev_xbrl_enrichment_derived_metrics` で新要素を活用した指標計算を実装
