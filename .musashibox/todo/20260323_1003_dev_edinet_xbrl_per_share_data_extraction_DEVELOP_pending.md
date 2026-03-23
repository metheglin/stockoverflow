# DEVELOP: EDINET XBRLから1株あたりデータ（EPS, BPS, 発行済株式数）を抽出する

## 概要

現在の `EdinetXbrlParser` は売上・利益・資産などの集計数値を抽出するが、1株あたりデータ（EPS, BPS, 配当金, 発行済株式数）を抽出していない。EDINET のみからインポートされた `FinancialValue`（JQUANTS データが存在しない企業・期間）では `eps`, `bps`, `shares_outstanding` が nil となり、バリュエーション指標（PER, PBR, PSR, 配当利回り）が算出不能となる。

## 背景・動機

### 現在のデータフロー

- **JQUANTS経由**: EPS, BPS, shares_outstanding, diluted_eps, treasury_shares が取得できる
- **EDINET経由**: これらのデータは EdinetXbrlParser で抽出されないため nil

### 影響のあるケース

1. **JQUANTS にデータがない期間**: 古い決算データ（JQUANTS のデータ範囲外）を EDINET から取得した場合
2. **非連結のみの企業**: JQUANTS は連結データのみ提供するが、EDINET からは個別データも取得可能。個別決算の FV には per-share データがない
3. **将来のEDINETファーストインポート**: EDINET を先にインポートし、後から JQUANTS で補完する運用の場合、一時的に per-share が欠落

### バリュエーション指標への影響

```ruby
# FinancialMetric.get_valuation_metrics (L110-128)
result["per"] = safe_divide(stock_price, fv.eps)  # eps が nil → PER 算出不能
result["pbr"] = safe_divide(stock_price, fv.bps)  # bps が nil → PBR 算出不能

# PSR算出にも shares_outstanding が必要
if fv.shares_outstanding.present?
  market_cap = stock_price * fv.shares_outstanding
  result["psr"] = (market_cap.to_d / fv.net_sales).to_f
end
```

## 実装内容

### 1. EdinetXbrlParser に ELEMENT_MAPPING を追加

```ruby
# 固定カラム対象の要素を追加
ELEMENT_MAPPING = {
  # ... 既存のマッピング ...

  # Per-share data
  eps: {
    elements: ["EarningsPerShare", "BasicEarningsLossPerShare"],
    namespace: "jppfs_cor",
  },
  diluted_eps: {
    elements: ["DilutedEarningsPerShare"],
    namespace: "jppfs_cor",
  },
  bps: {
    elements: ["NetAssetsPerShare", "BookValuePerShare"],
    namespace: "jppfs_cor",
  },
}.freeze
```

### 2. EXTENDED_ELEMENT_MAPPING に株式数を追加

```ruby
EXTENDED_ELEMENT_MAPPING = {
  # ... 既存のマッピング ...

  shares_outstanding: {
    elements: [
      "IssuedSharesTotalNumberOfSharesIssued",
      "TotalNumberOfIssuedShares",
    ],
    namespace: "jppfs_cor",
  },
  treasury_shares: {
    elements: ["TreasurySharesStock", "NumberOfTreasuryStock"],
    namespace: "jppfs_cor",
  },
}.freeze
```

### 3. DURATION_KEYS / INSTANT_KEYS の更新

```ruby
DURATION_KEYS = %i[
  net_sales operating_income ordinary_income net_income
  operating_cf investing_cf financing_cf
  cost_of_sales gross_profit sga_expenses
  eps diluted_eps  # EPS は duration (期間) コンテキスト
].freeze

INSTANT_KEYS = %i[
  total_assets net_assets cash_and_equivalents
  current_assets noncurrent_assets current_liabilities
  noncurrent_liabilities shareholders_equity
  shares_outstanding treasury_shares  # 株式数は instant (時点) コンテキスト
].freeze
```

### 4. ImportEdinetDocumentsJob#create_from_xbrl の更新

```ruby
def create_from_xbrl(fv, xbrl_values, report:)
  %i[net_sales operating_income ordinary_income net_income
     total_assets net_assets
     operating_cf investing_cf financing_cf cash_and_equivalents
     eps diluted_eps bps].each do |col|  # eps, diluted_eps, bps を追加
    fv.send(:"#{col}=", xbrl_values[col]) if xbrl_values.key?(col)
  end

  extended = xbrl_values[:extended] || {}
  fv.data_json = extended.transform_keys(&:to_s) if extended.any?

  # shares_outstanding, treasury_shares が extended にある場合は固定カラムに反映
  if extended[:shares_outstanding]
    fv.shares_outstanding = extended[:shares_outstanding]
  end
  if extended[:treasury_shares]
    fv.treasury_shares = extended[:treasury_shares]
  end

  fv.financial_report = report
  fv.save!
end
```

### 5. parse_numeric の拡張

EPS, BPS は小数値のため、Integer 変換でなく適切な型変換が必要:

```ruby
# eps, bps 用に小数パースを追加するか、
# extract_values で型を分岐させる
```

注: 現状の `parse_numeric` は `Integer(cleaned)` を試み、失敗時に `Float(cleaned).to_i` にフォールバックする。EPS=66.76 は 66 に切り捨てられてしまう。Decimal 対応が必要。

## テスト

- EdinetXbrlParser が EPS, BPS, 発行済株式数を正しく抽出できること
- EPS のような小数値が正確にパースされること（整数切り捨てされないこと）
- EDINET のみの FinancialValue に per-share データが入ること
- 既存の JQUANTS レコードを supplement する際に per-share データが上書きされないこと

## 注意事項

- EDINET XBRL の要素名は企業によって異なる場合があるため、候補配列で対応
- parse_numeric の変更は既存の整数パースに影響しないよう注意（EPSはDecimal, 売上はInteger）
- shares_outstanding は XBRL では「発行済株式総数」であり、自己株式を含む場合がある点に注意

## 優先度

中。EDINET のみの FinancialValue の完全性向上に寄与する。特に `parse_numeric` の小数切り捨てバグは EPS パースに直接影響するため、パーサー改修の一環として優先的に修正すべき。

## 関連TODO

- `20260322_1800_bugfix_roe_shareholders_equity` - shareholders_equity 取得と併せてデータ完全性が向上
- `20260322_1804_dev_cost_structure_breakdown_metrics` - EDINET 拡張データ活用の別の形
