# DEVELOP: インポート時の財務データ妥当性バリデーション

## 概要

FinancialValueのインポート（JQUANTS / EDINET）時に、取り込まれた値のドメイン的な妥当性を検証し、異常値を検出・記録する仕組みを実装する。

## 背景・動機

- 現在のDataIntegrityCheckJobは構造的な整合性（メトリクス欠損、同期鮮度等）を事後チェックするが、取り込まれた値そのものの妥当性は検証しない
- API提供元のデータに誤りがある場合（稀だが存在する）、異常値がそのまま取り込まれ、メトリクス計算結果にも伝播する
- 特にYoY成長率やROE等の指標は元データの品質に完全に依存しており、異常値が1件あるだけで連続成長カウンターがリセットされるなどの影響がある
- インポート時に検知できれば、問題のあるレコードにフラグを付けて分析時に除外する判断が可能になる

## 実装方針

### バリデーションモジュールの作成

`app/models/financial_value/reasonableness_validator.rb`

```ruby
class FinancialValue::ReasonablenessValidator
  # バリデーション結果
  # valid: 妥当性チェック通過
  # warnings: 疑わしいが致命的でない値
  # errors: 明らかに不正な値

  CHECKS = {
    total_assets: {
      error_if: ->(v) { v&.negative? },
      message: "total_assets is negative",
    },
    equity_ratio: {
      warning_if: ->(v) { v && (v < -50 || v > 100) },
      message: "equity_ratio outside expected range (-50..100)",
    },
    net_sales: {
      warning_if: ->(v) { v&.negative? },
      message: "net_sales is negative (unusual but possible for some industries)",
    },
    shares_outstanding: {
      error_if: ->(v) { v && v <= 0 },
      message: "shares_outstanding must be positive",
    },
    eps: {
      warning_if: ->(v, attrs) {
        v && attrs[:net_income] && attrs[:shares_outstanding] &&
          attrs[:shares_outstanding] > 0 &&
          (v - attrs[:net_income].to_f / attrs[:shares_outstanding]).abs > 100
      },
      message: "eps significantly differs from net_income / shares_outstanding",
    },
  }.freeze

  attr_reader :financial_value_attrs, :warnings, :errors

  def initialize(attrs)
    @financial_value_attrs = attrs
    @warnings = []
    @errors = []
  end

  def validate
    CHECKS.each do |column, check|
      value = @financial_value_attrs[column]

      if check[:error_if]
        result = check[:error_if].arity == 1 ?
          check[:error_if].call(value) :
          check[:error_if].call(value, @financial_value_attrs)
        @errors << { column: column, value: value, message: check[:message] } if result
      end

      if check[:warning_if]
        result = check[:warning_if].arity == 1 ?
          check[:warning_if].call(value) :
          check[:warning_if].call(value, @financial_value_attrs)
        @warnings << { column: column, value: value, message: check[:message] } if result
      end
    end

    self
  end

  def valid?
    @errors.empty?
  end

  def issues?
    @errors.any? || @warnings.any?
  end
end
```

### インポートジョブへの組み込み

ImportJquantsFinancialDataJob および ImportEdinetDocumentsJob のデータ取り込み箇所で、FinancialValueの属性を組み立てた後にバリデーションを実行する。

```ruby
# ImportJquantsFinancialDataJob#import_financial_value 内
attrs = FinancialValue.get_attributes_from_jquants(data, scope_type: scope_type)
validator = FinancialValue::ReasonablenessValidator.new(attrs).validate

if validator.issues?
  validator.warnings.each do |w|
    Rails.logger.warn("Reasonableness warning: company=#{company.name} #{w[:message]} (#{w[:column]}=#{w[:value]})")
  end
  validator.errors.each do |e|
    Rails.logger.error("Reasonableness error: company=#{company.name} #{e[:message]} (#{e[:column]}=#{e[:value]})")
  end
end

# errorsがある場合もインポート自体は実行する（データ提供元を信頼する方針）
# ただしログに記録し、後から問題のあるレコードを特定可能にする
```

### 前期比較によるスパイクチェック（オプション）

前期のFinancialValueが存在する場合、売上高や利益が前期比10倍以上に急変していないかをチェックする。急変自体は異常とは限らないが、注意すべき値として記録する。

## テスト

`spec/models/financial_value/reasonableness_validator_spec.rb`

- 正常な値 → valid?がtrueでwarnings/errorsが空
- total_assetsが負 → errorsに含まれる
- equity_ratioが200 → warningsに含まれる
- shares_outstandingが0 → errorsに含まれる
- 全値がnil → warningsもerrorsも空（nil値はチェック対象外）

## 依存関係

- 既存のImportJquantsFinancialDataJob、ImportEdinetDocumentsJobの動作を変更しない（ログ追加のみ）
- DataIntegrityCheckJob（事後チェック）と補完的関係
