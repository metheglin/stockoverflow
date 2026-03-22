# DEVELOP: インポートジョブのAPI障害時サーキットブレーカー

## 概要

長時間実行されるインポートジョブ（特に full モード）において、APIの認証失効・サービス障害・恒久的エラーが発生した場合、現状は個別リクエストごとにエラーをキャッチして続行するため、数千件の無駄なリクエストが発行され続ける。連続失敗を検出して早期中断するサーキットブレーカーを導入する。

## 背景・動機

### 現状の問題

**ImportJquantsFinancialDataJob#import_full:**
- Company.listed.find_each で全上場企業（約4,000社）を順次処理
- 1社あたり2秒のsleep → 全量処理に約2.2時間
- `Faraday::TooManyRequestsError` のみ re-raise で中断
- それ以外のエラー（401 Unauthorized, 500 Internal Server Error 等）は rescue で吸収して続行
- APIキーが失効した場合、4,000回の401エラーを出しながら2.2時間無駄に実行される

**ImportEdinetDocumentsJob:**
- 各日付の書類取得に失敗しても `process_date` 内で rescue して続行
- APIが長期停止している場合、全日付分の無駄なリクエストを発行

### 発生シナリオ

1. JQUANTSのリフレッシュトークンが期限切れ（id_token の有効期限は24時間）
2. EDINET APIの定期メンテナンス（毎月第3土曜日夜間）
3. ネットワーク障害（一時的だが復旧に時間がかかる場合）

## 実装方針

### サーキットブレーカーモジュール

```ruby
module ApiCircuitBreaker
  CONSECUTIVE_FAILURE_THRESHOLD = 5

  def reset_circuit_breaker
    @consecutive_failures = 0
  end

  def record_api_success
    @consecutive_failures = 0
  end

  def record_api_failure(error)
    @consecutive_failures = (@consecutive_failures || 0) + 1

    if @consecutive_failures >= CONSECUTIVE_FAILURE_THRESHOLD
      Rails.logger.error(
        "[#{self.class.name}] Circuit breaker triggered: " \
        "#{@consecutive_failures} consecutive failures. Last error: #{error.message}"
      )
      raise CircuitBreakerTripped.new(
        "API circuit breaker: #{@consecutive_failures} consecutive failures",
        last_error: error
      )
    end
  end

  class CircuitBreakerTripped < StandardError
    attr_reader :last_error
    def initialize(message, last_error: nil)
      @last_error = last_error
      super(message)
    end
  end
end
```

### 各ジョブへの組み込み

```ruby
class ImportJquantsFinancialDataJob < ApplicationJob
  include ApiCircuitBreaker

  def import_full
    reset_circuit_breaker

    Company.listed.find_each.with_index do |company, index|
      begin
        sleep(SLEEP_BETWEEN_REQUESTS) if index > 0
        statements = @client.load_financial_statements(code: company.securities_code)
        statements.each { |data| import_statement(data, company: company) }
        record_api_success
      rescue Faraday::TooManyRequestsError
        raise
      rescue => e
        @stats[:errors] += 1
        record_api_failure(e)  # 閾値超でCircuitBreakerTripped発生
        Rails.logger.error(...)
      end
    end
  end
end
```

### 設計上の注意

- CONSECUTIVE_FAILURE_THRESHOLD は定数として各ジョブで変更可能にする
- 429 (TooManyRequests) はサーキットブレーカーの対象外（既に re-raise で中断される）
- 一度成功すれば連続失敗カウンターはリセットされる（一時的なエラーでの誤発動防止）
- CircuitBreakerTripped はジョブの perform レベルで最終的にキャッチされ、ログ出力とともにジョブが終了する

## 優先度

中。運用開始後の実害に直結する。フルインポートの実行時間が長いため、早期中断の効果は大きい。
