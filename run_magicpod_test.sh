#!/bin/bash -e

OS=mac
FILENAME=magicpod-api-client

curl -L "https://app.magicpod.com/api/v1.0/magicpod-clients/api/${OS}/latest/" -H "Authorization: Token ${MAGICPOD_API_TOKEN}" --output ${FILENAME}.zip
unzip -q ${FILENAME}.zip

export MAGICPOD_ORGANIZATION=MagicPod_Sakakibara
export MAGICPOD_PROJECT=hands-on

TEST_SETTING_NUMBER=5

# バッチ実行（-eを無効化してexit codeを取得）
set +e
./magicpod-api-client batch-run -S ${TEST_SETTING_NUMBER}
EXIT_CODE=$?
set -e

echo ""
echo "=== テスト結果 ==="

if [ ${EXIT_CODE} -ne 0 ]; then
  echo "テストが成功しませんでした (exit code: ${EXIT_CODE})"
  echo ""
  echo "=== 失敗したテストのJira Issue作成 ==="

  # 最新のバッチ実行番号を取得
  LATEST_BATCH_RUN_INFO=$(curl -s -X 'GET' \
      "https://app.magicpod.com/api/v1.0/${MAGICPOD_ORGANIZATION}/${MAGICPOD_PROJECT}/batch-runs/?count=1&max_batch_run_number=50000" \
      -H "accept: application/json" \
      -H "Authorization: Token ${MAGICPOD_API_TOKEN}")

  LATEST_BATCH_RUN_NUMBER=$(echo "${LATEST_BATCH_RUN_INFO}" | jq -r '.batch_runs[0].batch_run_number')
  
  if [ -z "${LATEST_BATCH_RUN_NUMBER}" ]; then
    echo "エラー: バッチ実行番号を取得できませんでした"
    exit 1
  fi

  echo "一括実行番号: ${LATEST_BATCH_RUN_NUMBER}"
  
  # バッチ実行の詳細を取得
  BATCH_RUN_DETAILS=$(curl -s -X 'GET' \
      "https://app.magicpod.com/api/v1.0/MagicPod_Sakakibara/hands-on/batch-run/${LATEST_BATCH_RUN_NUMBER}/" \
      -H "accept: application/json" \
      -H "Authorization: Token ${MAGICPOD_API_TOKEN}")
  
  # 失敗したテストケース番号のリストを取得
  FAILED_TESTS=$(echo "${BATCH_RUN_DETAILS}" | jq -r '
    .test_cases.details[].results[] | 
    select(.status == "failed" or .status == "unresolved") | 
    .test_case.number
  ' | sort -u)
  
  # 失敗がなければ終了
  if [ -z "${FAILED_TESTS}" ]; then
    echo "失敗したテストが見つかりませんでした"
    exit 0
  fi
  
  echo "=== 失敗テスト検出 ==="
  
  # 失敗した各テストに対してJira Issueを作成
for TEST_NUM in ${FAILED_TESTS}; do
  echo "テストケース #${TEST_NUM} のIssue作成中..."
  
  # 変数名を修正（MAGICPOD_ORGANIZATION と MAGICPOD_PROJECT を使用）
  RESULT_URL="https://app.magicpod.com/${MAGICPOD_ORGANIZATION}/${MAGICPOD_PROJECT}/batch-run/${LATEST_BATCH_RUN_NUMBER}/${TEST_NUM}/"
  
  # Jira環境変数のチェック
  if [ -z "${JIRA_URL}" ] || [ -z "${JIRA_EMAIL}" ] || [ -z "${JIRA_API_TOKEN}" ] || [ -z "${JIRA_PROJECT_KEY}" ]; then
    echo "✗ エラー: Jira環境変数が設定されていません"
    echo "  JIRA_URL: ${JIRA_URL:-未設定}"
    echo "  JIRA_EMAIL: ${JIRA_EMAIL:-未設定}"
    echo "  JIRA_PROJECT_KEY: ${JIRA_PROJECT_KEY:-未設定}"
    continue
  fi
  
  # デバッグ情報
  echo "Jira URL: ${JIRA_URL}"
  echo "Jira Email: ${JIRA_EMAIL}"
  echo "Project Key: ${JIRA_PROJECT_KEY}"
  
  # Jira API呼び出し（エラーでも継続）
  set +e
  JIRA_RESPONSE=$(curl -s -L -w "\n%{http_code}" -X POST "${JIRA_URL}/rest/api/3/issue" \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"${JIRA_PROJECT_KEY}\"},
      \"summary\": \"[MagicPod] テスト失敗: #${TEST_NUM}\",
      \"description\": {
        \"type\": \"doc\",
        \"version\": 1,
        \"content\": [
          {
            \"type\": \"paragraph\",
            \"content\": [
              {
                \"type\": \"text\",
                \"text\": \"バッチ実行 #${LATEST_BATCH_RUN_NUMBER} でテストケース #${TEST_NUM} が失敗しました。\"
              }
            ]
          },
          {
            \"type\": \"paragraph\",
            \"content\": [
              {
                \"type\": \"text\",
                \"text\": \"結果URL: \",
                \"marks\": [{\"type\": \"strong\"}]
              },
              {
                \"type\": \"text\",
                \"text\": \"${RESULT_URL}\",
                \"marks\": [{
                  \"type\": \"link\",
                  \"attrs\": {\"href\": \"${RESULT_URL}\"}
                }]
              }
            ]
          }
        ]
      },
      \"issuetype\": {\"name\": \"タスク\"},
      \"labels\": [\"magicpod\", \"test-failure\"]
    }
  }")
  CURL_EXIT_CODE=$?
  set -e
  
  # HTTPステータスコードを取得
  HTTP_CODE=$(echo "${JIRA_RESPONSE}" | tail -n1)
  RESPONSE_BODY=$(echo "${JIRA_RESPONSE}" | sed '$d')
  
  echo "HTTP Status: ${HTTP_CODE}"
  echo "Response Body: ${RESPONSE_BODY}"
  
  # Issue作成結果を表示
  if [ ${CURL_EXIT_CODE} -ne 0 ]; then
    echo "✗ Jira API呼び出し失敗 (exit code: ${CURL_EXIT_CODE})"
  elif [ "${HTTP_CODE}" = "201" ]; then
    ISSUE_KEY=$(echo "${RESPONSE_BODY}" | jq -r '.key // empty')
    if [ -n "${ISSUE_KEY}" ]; then
      echo "✓ Issue作成成功: ${ISSUE_KEY}"
    else
      echo "✗ Issue作成失敗（レスポンスにkeyがありません）"
    fi
  else
    echo "✗ Issue作成失敗 (HTTP ${HTTP_CODE})"
    echo "エラー詳細: ${RESPONSE_BODY}"
  fi
done

  echo ""
  echo "=== 完了 ==="
  exit 1

else
  echo "✓ テスト成功"
  exit 0
fi
