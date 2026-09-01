#!/bin/bash

# 1Panel 多节点证书上传脚本，无外部配置文件
# 新增站点：复制一份【单个站点调用块】修改内部参数即可
# 依赖：jq
# 用法：
# ./script.sh                 # 使用脚本目录 fullchain.pem privkey.pem
# ./script.sh /opt/xxx/ssl    # 指定证书目录

set -eo pipefail

### ==========================================================
### 全局固定参数 
TIME_ZONE="Asia/Shanghai"
API_SSL_UPLOAD="/api/v2/websites/ssl/upload"

# 脚本文件真实路径
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")

# 证书目录，支持传入参数
PEM_PATH="${1:-${SCRIPT_DIR}}"
FULLCHAIN_PEM="${PEM_PATH}/fullchain.pem"
PRIVKEY_PEM="${PEM_PATH}/privkey.pem"

### ==========================================================
### 工具函数 
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}
die() {
    log "ERROR: $1" >&2
    exit 1
}

# 解析json code字段，依赖jq
get_json_code() {
    local json_str="$1"
    echo "${json_str}" | jq -r '.code'
}

#----------------------------------------------------------------------
# 通用失败重试封装函数
# $1:最大重试次数
# $2:失败等待秒数
# $@:待执行的命令以及全部参数
# 返回：0执行成功；1多次重试后仍然失败
#----------------------------------------------------------------------
run_with_retry() {
    local max_retry="$1"
    local sleep_sec="$2"
    shift 2

    local count=0
    while true; do
        # 执行业务函数
        if "$@"; then
            return 0
        fi
        count=$((count + 1))
        if [[ $count -ge "${max_retry}" ]]; then
            log "已达到最大重试 ${max_retry} 次，放弃该任务"
            return 1
        fi
        log "第 ${count} 次执行失败，等待 ${sleep_sec}s 后重试..."
        sleep "${sleep_sec}"
    done
}

#----------------------------------------------------------------------
# 单个站点上传函数，每个站点传自己的参数
# $1: PANEL_URL
# $2: API_SECRET
# $3: SSL_ID
# $4: DESCRIPTION
#----------------------------------------------------------------------
upload_one_site(){
    local PANEL_URL="$1"
    local API_SECRET="$2"
    local SSL_ID="$3"
    local DESCRIPTION="$4"
    log "========================================"
    log "开始处理站点：panel=${PANEL_URL} ssl_id=${SSL_ID} desc=${DESCRIPTION}"

    # mm
    local current_time=$(TZ=$TIME_ZONE date '+%Y-%m-%d %H:%M:%S')

    local UPLOAD_DATA=$(cat <<EOF
{
    "privateKey": "$PRIVATE_KEY_CONTENT",
    "certificate": "$CERTIFICATE_CONTENT",
    "type": "paste",
    "sslID": $SSL_ID,
    "description": "${DESCRIPTION} ${current_time}"
}
EOF
    )

    # 生成1panel需要的Token：md5(1panel+SECRET+unix_stamp)
    local TIMESTAMP=$(date +%s)
    local TOKEN_MD5=$(echo -n "1panel${API_SECRET}${TIMESTAMP}"|md5sum |cut -d" " -f1)

    # 发送证书上传请求，全部header使用标准半角减号
    local UPLOAD_RESPONSE curl_exit_code RESP_BODY HTTP_CODE
    set +e
    UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${PANEL_URL}${API_SSL_UPLOAD}" \
        -H "Content-Type: application/json" \
        -H "1Panel-Token: $TOKEN_MD5" \
        -H "1Panel-Timestamp: $TIMESTAMP" \
        -d "$UPLOAD_DATA")
    curl_exit_code=$?
    set -e

    RESP_BODY=$(echo "${UPLOAD_RESPONSE}" | head -n -1)
    HTTP_CODE=$(echo "${UPLOAD_RESPONSE}" | tail -n1)

    if [[ ${curl_exit_code} -ne 0 ]];then
        log "ERROR: curl网络失败, curl_exit_code=${curl_exit_code}"
        return 1
    fi
    if [[ "${HTTP_CODE}" != "200" ]];then
        log "ERROR: HTTP状态码非200，http_code=${HTTP_CODE}, resp=${RESP_BODY}"
        return 1
    fi

    local resp_code=$(get_json_code "${RESP_BODY}")
    if [[ "${resp_code}" == "200" ]]; then
        log "上传成功, resp:${RESP_BODY}"
        return 0
    else
        log "业务返回错误 code=${resp_code}, resp:${RESP_BODY}"
        return 1
    fi
}

### 脚本初始化校验 ==========================================================
[[ ! -f "${FULLCHAIN_PEM}" ]] && die "证书文件：${FULLCHAIN_PEM}未找到"
[[ ! -f "${PRIVKEY_PEM}" ]] && die "密钥文件：${PRIVKEY_PEM}未找到"

if ! command -v jq &>/dev/null; then
    die "未安装 jq，请先安装jq"
fi

# 预处理证书PEM内容，转义换行符
PRIVATE_KEY_CONTENT=$(cat "$PRIVKEY_PEM" | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
CERTIFICATE_CONTENT=$(cat "$FULLCHAIN_PEM" | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

## =================================
# 在这里填写你的所有站点，使用 run_with_retry 包裹调用
# 格式： run_with_retry 最大重试次数 间隔秒数 upload_one_site 面板地址 API密钥 ssl_id 描述

run_with_retry 3 2 upload_one_site "https://mson.bbroot.com" "u0105Ttx1bFpQHZcMEtIOTtKzaRKtuXM" "5" "aliyun"

# run_with_retry 3 2 upload_one_site "https://xxx" "secret" "22" "hk‑site"
# 需要新增站点，直接复制上面一行修改参数

log "===== 全部站点执行完毕 ====="
exit 0
