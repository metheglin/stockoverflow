# Bugfix JQUANTS Daily Quotes

ImportDailyQuotesJobを実行すると、途中から以下のエラーが繰り返し発生する。

> Your subscription covers the following dates: 2024-01-01 ~ 2026-01-01. If you want more data, please check other plans:https://jpx-jquants.com/#dataset

このプラン（おそらく無料プラン）で利用できる期限のルールを調査し、その期限内のデータのみ取得するように修正して。

また、このAPIエラーが繰り返し何度も発生する場合、バルク処理をあきらめて異常終了するようにジョブを設計して。

■エラー時のレスポンス

```
status: 400, 
headers: {"date" => "Thu, 26 Mar 2026 08:46:50 GMT", "content-type" => "application/json", "content-length" => "154", "connection" => "keep-alive", "x-amzn-requestid" => "9aaf43a2-6928-4176-9d9d-e5240cc50a8a", "access-control-allow-origin" => "*", "content-encoding" => "gzip", "strict-transport-security" => "max-age=31536000", "x-amz-apigw-id" => "a0rTQGKkNjMED-w=", "x-amzn-trace-id" => "Root=1-69c4f27a-51f9153920181dc64b52a35b"}, 
body: "{\"message\": \"Your subscription covers the following dates: 2024-01-01 ~ 2026-01-01. If you want more data, please check other plans:https://jpx-jquants.com/#dataset\"}"
```