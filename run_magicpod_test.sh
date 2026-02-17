#!/bin/bash -e

OS=mac
FILENAME=magicpod-api-client

curl -L "https://app.magicpod.com/api/v1.0/magicpod-clients/api/${OS}/latest/" -H "Authorization: Token ${MAGICPOD_API_TOKEN}" --output ${FILENAME}.zip
unzip -q ${FILENAME}.zip

export MAGICPOD_ORGANIZATION=MagicPod_Sakakibara
export MAGICPOD_PROJECT=hands-on

TEST_SETTING_NUMBER=5

# バッチ実行
./magicpod-api-client batch-run -S ${TEST_SETTING_NUMBER}
EXIT_CODE=$?

./magicpod-api-client get-batch-run

echo "=== テスト結果 ==="
if [ ${EXIT_CODE} -ne 0 ]; then
  echo "テストが成功しませんでした (exit code: ${EXIT_CODE})"

  echo "=== テスト結果を取得してjira Issueを作成 ==="

  # 最新のバッチ実行番号を取得
  BATCH_RUN_NUM=$(curl -s "https://app.magicpod.com/api/v1.0/${MAGICPOD_ORGANIZATION}/${MAGICPOD_PROJECT}/batch-run/" \
    -H "Authorization: Token ${MAGICPOD_API_TOKEN}" | jq -r '.[0].batch_run_number')
  echo "バッチ実行番号: ${BATCH_RUN_NUM}"
  
  # バッチ実行の詳細を取得
  BATCH_DETAILS=$(curl -s "https://app.magicpod.com/api/v1.0/${MAGICPOD_ORGANIZATION}/${MAGICPOD_PROJECT}/batch-run/${BATCH_RUN_NUM}/" \
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

else
  echo "テスト成功"
fi
