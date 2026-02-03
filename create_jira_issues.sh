#!/bin/bash -e

# 設定
MAGICPOD_ORG="MagicPod_Sakakibara"
MAGICPOD_PROJ="hands-on"

echo "=== MagicPodテスト結果を取得中 ==="

# 最新のバッチ実行番号を取得
BATCH_RUN_NUM=$(curl -s "https://app.magicpod.com/api/v1.0/${MAGICPOD_ORG}/${MAGICPOD_PROJ}/batch-run/" \
  -H "Authorization: Token ${MAGICPOD_API_TOKEN}" | jq -r '.[0].batch_run_number')

[ -z "${BATCH_RUN_NUM}" ] && echo "バッチ実行が見つかりません" && exit 0

echo "バッチ実行番号: ${BATCH_RUN_NUM}"

# バッチ実行の詳細を取得
BATCH_DETAILS=$(curl -s "https://app.magicpod.com/api/v1.0/${MAGICPOD_ORG}/${MAGICPOD_PROJ}/batch-run/${BATCH_RUN_NUM}/" \
  -H "Authorization: Token ${MAGICPOD_API_TOKEN}")

# 失敗したテストケース番号のリストを取得
FAILED_TESTS=$(echo "${BATCH_DETAILS}" | jq -r '.test_cases.details[] | select(.status == "failed" or .status == "unresolved") | .test_case_number')

# 失敗がなければ終了
[ -z "${FAILED_TESTS}" ] && echo "✓ すべて成功しました" && exit 0

echo "=== 失敗テスト検出 ==="

# 失敗した各テストに対してJira Issueを作成
for TEST_NUM in ${FAILED_TESTS}; do
  echo "テストケース #${TEST_NUM} のIssue作成中..."
  
  RESULT_URL="https://app.magicpod.com/${MAGICPOD_ORG}/${MAGICPOD_PROJ}/batch-run/${BATCH_RUN_NUM}/${TEST_NUM}/1/0/"
  
  curl -s -X POST "${JIRA_URL}/rest/api/3/issue" \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "fields": {
        "project": {"key": "'"${JIRA_PROJECT_KEY}"'"},
        "summary": "[MagicPod] テスト失敗: #'"${TEST_NUM}"'",
        "description": "テストケース #'"${TEST_NUM}"' が失敗しました。\n\n結果: '"${RESULT_URL}"'",
        "issuetype": {"name": "Bug"},
        "labels": ["magicpod", "test-failure"]
      }
    }' | jq -r '"✓ Issue作成: " + .key'
done

echo "=== 完了 ==="
