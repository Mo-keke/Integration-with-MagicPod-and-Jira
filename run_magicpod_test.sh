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
  LATEST_BATCH_RUN_INFO=$(curl -X 'GET' \
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
  LATEST_BATCH_RUN_DETAILS=$(curl -X 'GET' \
      "https://app.magicpod.com/api/v1.0/MagicPod_Sakakibara/hands-on/batch-run/${LATEST_BATCH_RUN_NUMBER}/" \
      -H "accept: application/json" \
      -H "Authorization: Token ${MAGICPOD_API_TOKEN}")
  
  # 失敗したテストケース番号のリストを取得
  FAILED_TEST_INFO=$(echo "${LATEST_BATCH_RUN_DETAILS}" | jq -r '
    .test_cases.details[] | 
    .pattern.number as $pattern_num | 
    .results[] | 
    select(.status == "failed" or .status == "unresolved") | 
    "\(.test_case.number)|\(.test_case.name)|\($pattern_num)|\(.number)"
  ')
  
  # 失敗がなければ終了
  if [ -z "${FAILED_TEST_INFO}" ]; then
    echo "失敗したテストが見つかりませんでした"
    exit 0
  fi
  
  echo "=== 失敗テスト検出 ==="
  
  # 失敗した各テストに対してJira Issueを作成
  echo "${FAILED_TEST_INFO}" | while IFS='|' read TEST_CASE_NUM TEST_CASE_NAME PATTERN_NUM RUN_NUM; do
    echo "テストケース #${TEST_CASE_NUM} (${TEST_CASE_NAME}) のIssue作成中..."
    
    # テスト結果URL
    RESULT_URL="https://app.magicpod.com/${MAGICPOD_ORGANIZATION}/${MAGICPOD_PROJECT}/batch-run/${LATEST_BATCH_RUN_NUMBER}/${PATTERN_NUM}/${RUN_NUM}/1/"
    
    JIRA_RESPONSE=$(curl -s -X POST "${JIRA_URL}/rest/api/3/issue" \
      -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"fields\": {
          \"project\": {\"key\": \"${JIRA_PROJECT_KEY}\"},
          \"summary\": \"[MagicPod] テスト失敗: #${TEST_CASE_NUM} ${TEST_CASE_NAME}\",
          \"description\": \"バッチ実行 #${LATEST_BATCH_RUN_NUMBER} でテストケース #${TEST_CASE_NUM} (${TEST_CASE_NAME}) が失敗しました。\n\n結果URL: ${RESULT_URL}\",
          \"issuetype\": {\"name\": \"Bug\"},
          \"labels\": [\"magicpod\", \"test-failure\"]
        }
      }")
    
    # Issue作成結果を表示
    ISSUE_KEY=$(echo "${JIRA_RESPONSE}" | jq -r '.key // empty')
    if [ -n "${ISSUE_KEY}" ]; then
      echo "✓ Issue作成成功: ${ISSUE_KEY}"
    else
      echo "✗ Issue作成失敗"
      ERROR_MSG=$(echo "${JIRA_RESPONSE}" | jq -r '.errors // .errorMessages // "不明なエラー"')
      echo "エラー詳細: ${ERROR_MSG}"
    fi
  done
  
  echo ""
  echo "=== 完了 ==="
  exit 1
  
else
  echo "✓ テスト成功"
  exit 0
fi
