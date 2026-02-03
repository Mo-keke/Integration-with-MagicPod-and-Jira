#!/bin/bash -e

OS=mac
FILENAME=magicpod-api-client

curl -L "https://app.magicpod.com/api/v1.0/magicpod-clients/api/${OS}/latest/" -H "Authorization: Token ${MAGICPOD_API_TOKEN}" --output ${FILENAME}.zip
unzip -q ${FILENAME}.zip

export MAGICPOD_ORGANIZATION=MagicPod_Sakakibara
export MAGICPOD_PROJECT=hands-on

TEST_SETTING_NUMBER=5

# -e オプションを一時的に無効化
set +e

# バッチ実行
./magicpod-api-client batch-run -S ${TEST_SETTING_NUMBER}
EXIT_CODE=$?

# -e オプションを再度有効化
set -e

echo "=== テスト結果 ==="
if [ ${EXIT_CODE} -ne 0 ]; then
  echo "テスト失敗を検出 (exit code: ${EXIT_CODE})"
  exit 1
else
  echo "テスト成功"
  exit 0
fi
