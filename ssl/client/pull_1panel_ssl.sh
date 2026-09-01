#!/bin/bash
set -eo pipefail

########################## 配置区 ##########################
# 阿里云服务器
ALIYUN_SSH_HOST="115.29.215.239"
ALIYUN_SSH_PORT="22"
ALIYUN_SSH_USER="root"
ALI_FULLCHAIN="/opt/1panel/ssl-helper/fullchain.pem"
ALI_PRIVKEY="/opt/1panel/ssl-helper/privkey.pem"

# 香港本地临时存放
LOC_FULLCHAIN="/tmp/pull_fullchain.pem"
LOC_PRIVKEY="/tmp/pull_privkey.pem"

# 1Panel站点根目录（你提供真实路径）
SITE_ROOT="/opt/1panel/www/sites"
# 只匹配结尾为 xuechun.vip 的域名
SUFFIX_MATCH="xuechun.vip"
###########################################################

# 1.香港主动sftp拉取阿里云证书
sftp -P ${ALIYUN_SSH_PORT} ${ALIYUN_SSH_USER}@${ALIYUN_SSH_HOST} <<EOF
get ${ALI_FULLCHAIN} ${LOC_FULLCHAIN}
get ${ALI_PRIVKEY} ${LOC_PRIVKEY}
exit
EOF

# 校验下载结果
if [[ ! -f "${LOC_FULLCHAIN}" || ! -f "${LOC_PRIVKEY}" ]]; then
    echo "$(date) ERROR: 从阿里云下载证书失败"
    exit 1
fi

# 2.遍历站点目录，只处理域名结尾 xuechun.vip
# 遍历sites下每一个站点文件夹
for site_dir in "${SITE_ROOT}"/*; do
    [[ ! -d "${site_dir}" ]] && continue
    ssl_dir="${site_dir}/ssl"
    # ssl目录必须存在且两个证书文件存在才处理
    if [[ ! -f "${ssl_dir}/fullchain.pem" || ! -f "${ssl_dir}/privkey.pem" ]]; then
        continue
    fi

    # 从站点文件夹名称提取域名，匹配后缀 xuechun.vip
    site_name=$(basename "${site_dir}")
    if [[ "${site_name}" == *"${SUFFIX_MATCH}" ]]; then
        echo "$(date) 更新站点: ${site_name}"
        cp -f "${LOC_FULLCHAIN}" "${ssl_dir}/fullchain.pem"
        cp -f "${LOC_PRIVKEY}" "${ssl_dir}/privkey.pem"
    fi
done

# 3.获取运行中的openresty容器，你的容器名称为 openresty
CONTAINER=$(docker ps --filter "status=running" --filter "name=^openresty$" --format '{{.Names}}')
if [[ -z "${CONTAINER}" ]];then
    echo "$(date) WARN: 未找到运行的openresty容器，证书文件已替换，请手动重载服务"
else
    echo "$(date) 检测到openresty容器: ${CONTAINER}"
    # 先校验配置语法，有错直接退出，不重载（防止网站瘫痪）
    if ! docker exec "${CONTAINER}" openresty -t; then
        echo "$(date) ERROR: openresty配置语法错误，放弃重载"
        rm -f "${LOC_FULLCHAIN}" "${LOC_PRIVKEY}"
        exit 1
    fi
    # 平滑重载openresty，无停机
    docker exec "${CONTAINER}" openresty -s reload
    echo "$(date) openresty 平滑重载完成"
fi

echo "$(date) 证书更新流程结束"
# 清理临时文件
rm -f "${LOC_FULLCHAIN}" "${LOC_PRIVKEY}"
