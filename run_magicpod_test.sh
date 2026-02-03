#!/bin/bash -e

OS=mac
FILENAME=magicpod-api-client

curl -L "https://app.magicpod.com/api/v1.0/magicpod-clients/api/${OS}/latest/" -H "Authorization: Token ${MAGICPOD_API_TOKEN}" --output ${FILENAME}.zip
unzip -q ${FILENAME}.zip

export MAGICPOD_ORGANIZATION=MagicPod_Sakakibara
export MAGICPOD_PROJECT=hands-on

TEST_SETTING_NUMBER=5

./magicpod-api-client batch-run -S ${TEST_SETTING_NUMBER}
