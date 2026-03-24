# DEVELOP: EdinetXbrlParser jppfs_cor 要素拡張（P/L・B/S・C/F追加要素）

## 概要

EdinetXbrlParser の EXTENDED_ELEMENT_MAPPING に jppfs_cor 名前空間の追加要素を実装し、FinancialValue の data_json スキーマを拡張する。P/L の損益構造詳細、B/S の有利子負債・運転資本項目、C/F の減価償却費を抽出可能にする。

## 背景・動機

### 現状

EdinetXbrlParser は jppfs_cor 名前空間から19要素（固定カラム11 + 拡張8）を抽出している。これにより基本的なP/L・B/S・C/F分析は可能だが、以下の分析に必要なデータが不足している:

- **EBITDA精緻化**: 現在の FinancialMetric.get_ev_ebitda は `operating_income` をEBITDA代替としているが、`減価償却費`があれば `営業利益 + 減価償却費` でより正確なEBITDAを算出可能
- **有利子負債の精密分析**: 現在 `get_financial_health_metrics` は `(current_liabilities + noncurrent_liabilities - net_assets)` で有利子負債を推定しているが、短期借入金・長期借入金・社債があれば正確な値を利用可能
- **運転資本・CCC分析**: 売掛金・棚卸資産・買掛金のデータがあれば、キャッシュ・コンバージョン・サイクル（CCC）を算出可能
- **P/L損益構造の分析**: 特別損益・法人税等・営業外損益の内訳により、利益の質・持続性を評価可能

### 対象企業への影響

全てのEDINET報告企業に恩恵がある。特にJQUANTSで取得できないこれらの詳細データはEDINET XBRLのみから得られる独自価値である。

## 追加するXBRL要素一覧

### P/L（損益計算書）追加要素 — durationコンテキスト

| data_json キー | XBRL要素候補 | 名前空間 | 説明 |
|---|---|---|---|
| `non_operating_income` | NonOperatingIncome | jppfs_cor | 営業外収益 |
| `non_operating_expenses` | NonOperatingExpenses | jppfs_cor | 営業外費用 |
| `interest_expense` | InterestExpense, InterestExpensesNOE | jppfs_cor | 支払利息 |
| `extraordinary_income` | ExtraordinaryIncome | jppfs_cor | 特別利益 |
| `extraordinary_loss` | ExtraordinaryLoss | jppfs_cor | 特別損失 |
| `income_before_income_taxes` | IncomeBeforeIncomeTaxes | jppfs_cor | 税引前当期純利益 |
| `income_taxes` | IncomeTaxes | jppfs_cor | 法人税等合計 |

### B/S（貸借対照表）追加要素 — instantコンテキスト

| data_json キー | XBRL要素候補 | 名前空間 | 説明 |
|---|---|---|---|
| `short_term_loans_payable` | ShortTermLoansPayable, ShortTermBorrowings | jppfs_cor | 短期借入金 |
| `long_term_loans_payable` | LongTermLoansPayable, LongTermDebt | jppfs_cor | 長期借入金 |
| `bonds_payable` | BondsPayable, Bonds | jppfs_cor | 社債 |
| `total_liabilities` | Liabilities | jppfs_cor | 負債合計 |
| `retained_earnings` | RetainedEarnings | jppfs_cor | 利益剰余金 |
| `inventories` | Inventories, MerchandiseAndFinishedGoods | jppfs_cor | 棚卸資産 |
| `notes_and_accounts_receivable` | NotesAndAccountsReceivableTrade, AccountsReceivableTrade | jppfs_cor | 受取手形及び売掛金 |
| `notes_and_accounts_payable` | NotesAndAccountsPayableTrade, AccountsPayableTrade | jppfs_cor | 支払手形及び買掛金 |
| `goodwill` | Goodwill, GoodwillNet | jppfs_cor | のれん |
| `intangible_assets` | IntangibleAssets | jppfs_cor | 無形固定資産 |

### C/F（キャッシュフロー計算書）追加要素 — durationコンテキスト

| data_json キー | XBRL要素候補 | 名前空間 | 説明 |
|---|---|---|---|
| `depreciation_and_amortization` | DepreciationAndAmortizationOpeCF, DepreciationAndAmortization | jppfs_cor | 減価償却費 |

## 実装内容

### 1. EdinetXbrlParser の EXTENDED_ELEMENT_MAPPING に追加

```ruby
EXTENDED_ELEMENT_MAPPING = {
  # ... 既存の8要素 ...

  # P/L 追加要素
  non_operating_income: {
    elements: ["NonOperatingIncome"],
    namespace: "jppfs_cor",
  },
  non_operating_expenses: {
    elements: ["NonOperatingExpenses"],
    namespace: "jppfs_cor",
  },
  interest_expense: {
    elements: ["InterestExpense", "InterestExpensesNOE"],
    namespace: "jppfs_cor",
  },
  extraordinary_income: {
    elements: ["ExtraordinaryIncome"],
    namespace: "jppfs_cor",
  },
  extraordinary_loss: {
    elements: ["ExtraordinaryLoss"],
    namespace: "jppfs_cor",
  },
  income_before_income_taxes: {
    elements: ["IncomeBeforeIncomeTaxes"],
    namespace: "jppfs_cor",
  },
  income_taxes: {
    elements: ["IncomeTaxes"],
    namespace: "jppfs_cor",
  },

  # B/S 追加要素
  short_term_loans_payable: {
    elements: ["ShortTermLoansPayable", "ShortTermBorrowings"],
    namespace: "jppfs_cor",
  },
  long_term_loans_payable: {
    elements: ["LongTermLoansPayable", "LongTermDebt"],
    namespace: "jppfs_cor",
  },
  bonds_payable: {
    elements: ["BondsPayable", "Bonds"],
    namespace: "jppfs_cor",
  },
  total_liabilities: {
    elements: ["Liabilities"],
    namespace: "jppfs_cor",
  },
  retained_earnings: {
    elements: ["RetainedEarnings"],
    namespace: "jppfs_cor",
  },
  inventories: {
    elements: ["Inventories", "MerchandiseAndFinishedGoods"],
    namespace: "jppfs_cor",
  },
  notes_and_accounts_receivable: {
    elements: ["NotesAndAccountsReceivableTrade", "AccountsReceivableTrade"],
    namespace: "jppfs_cor",
  },
  notes_and_accounts_payable: {
    elements: ["NotesAndAccountsPayableTrade", "AccountsPayableTrade"],
    namespace: "jppfs_cor",
  },
  goodwill: {
    elements: ["Goodwill", "GoodwillNet"],
    namespace: "jppfs_cor",
  },
  intangible_assets: {
    elements: ["IntangibleAssets"],
    namespace: "jppfs_cor",
  },

  # C/F 追加要素
  depreciation_and_amortization: {
    elements: ["DepreciationAndAmortizationOpeCF", "DepreciationAndAmortization"],
    namespace: "jppfs_cor",
  },
}.freeze
```

### 2. DURATION_KEYS / INSTANT_KEYS の更新

```ruby
DURATION_KEYS = %i[
  net_sales operating_income ordinary_income net_income
  operating_cf investing_cf financing_cf
  cost_of_sales gross_profit sga_expenses
  non_operating_income non_operating_expenses interest_expense
  extraordinary_income extraordinary_loss
  income_before_income_taxes income_taxes
  depreciation_and_amortization
].freeze

INSTANT_KEYS = %i[
  total_assets net_assets cash_and_equivalents
  current_assets noncurrent_assets current_liabilities
  noncurrent_liabilities shareholders_equity
  short_term_loans_payable long_term_loans_payable bonds_payable
  total_liabilities retained_earnings
  inventories notes_and_accounts_receivable notes_and_accounts_payable
  goodwill intangible_assets
].freeze
```

### 3. FinancialValue の data_json スキーマ拡張

```ruby
define_json_attributes :data_json, schema: {
  # ... 既存のスキーマ ...

  # P/L 追加
  non_operating_income: { type: :integer },
  non_operating_expenses: { type: :integer },
  interest_expense: { type: :integer },
  extraordinary_income: { type: :integer },
  extraordinary_loss: { type: :integer },
  income_before_income_taxes: { type: :integer },
  income_taxes: { type: :integer },

  # B/S 追加
  short_term_loans_payable: { type: :integer },
  long_term_loans_payable: { type: :integer },
  bonds_payable: { type: :integer },
  total_liabilities: { type: :integer },
  retained_earnings: { type: :integer },
  inventories: { type: :integer },
  notes_and_accounts_receivable: { type: :integer },
  notes_and_accounts_payable: { type: :integer },
  goodwill: { type: :integer },
  intangible_assets: { type: :integer },

  # C/F 追加
  depreciation_and_amortization: { type: :integer },
}
```

### 4. ImportEdinetDocumentsJob への影響

変更不要。`supplement_with_xbrl` と `create_from_xbrl` は `xbrl_values[:extended]` を動的に処理するため、パーサー側の拡張のみで新要素が自動的にdata_jsonに格納される。

## テスト

### EdinetXbrlParser のテスト

- 各追加要素が正しいコンテキスト（duration/instant）で抽出されること
- 要素候補の配列フォールバック（例: ShortTermLoansPayable → ShortTermBorrowings）が機能すること
- 要素が存在しない場合にnilが返ること（既存動作と同様）
- 既存の19要素の抽出に影響がないこと

### データ格納のテスト

- 新規XBRL取込時にdata_jsonに追加要素が格納されること
- 既存レコードへのsupplement時に追加要素がマージされること

## 可能になる分析指標（後続TODOで実装）

| 指標 | 算出式 | 必要要素 |
|---|---|---|
| EBITDA（精緻版） | operating_income + depreciation_and_amortization | depreciation_and_amortization |
| 有利子負債 | short_term_loans + long_term_loans + bonds | 有利子負債3要素 |
| D/E比率（精緻版） | interest_bearing_debt / shareholders_equity | 有利子負債 + shareholders_equity |
| CCC | 売上債権回転日数 + 棚卸資産回転日数 - 仕入債務回転日数 | receivable, inventories, payable |
| 実効税率 | income_taxes / income_before_income_taxes | income_taxes, income_before_income_taxes |
| のれん比率 | goodwill / total_assets | goodwill |
| R&D集約度 | (後続TODOで jpcrp_cor から取得) | — |

## 注意事項

- 全て jppfs_cor 名前空間のため、既存の register_namespaces で対応済み
- 要素名が企業によって異なる可能性があるため、候補配列で対応している
- マイナス値の要素（支払利息、特別損失等）は既存の parse_numeric で正しく処理される
- 金融業（銀行・保険・証券）は勘定科目体系が異なるため、一部要素が取得できない場合がある

## 優先度

高。有利子負債の精密化と減価償却費によるEBITDA精緻化は、現行のバリュエーション分析・財務健全性分析の精度向上に直結する。

## 依存関係

- なし（既存のパーサー構造に追加するのみ）
- 後続: `dev_xbrl_enrichment_derived_metrics` で新要素を活用した指標計算を実装
