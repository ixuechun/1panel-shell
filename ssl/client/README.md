# pull_1panel_ssl

## 功能简介
> 1panel客户端节点从主节点自动下载更新证书，脚本运行在**香港1Panel服务器**。
主动通过 sftp 从阿里云服务器拉取最新SSL证书，批量更新本机所有后缀为 `xuechun.vip` 的1Panel站点磁盘证书文件；完成后校验OpenResty配置语法，平滑重载OpenResty容器，实现证书续期。

> 重要特性：
1. **只修改磁盘证书文件，不会更新1Panel数据库内证书记录**，网页面板证书列表不会刷新；HTTPS访问直接读取磁盘pem文件，业务正常生效。
2. OpenResty配置语法出错时直接放弃重载，避免全站502故障。
3. OpenResty容器未找到仅告警，不终止脚本，证书文件已经写入，需要人工手动重载服务。
4. 使用 sftp 拉取证书，目标阿里云SSH端口非默认22端口。

## 环境依赖
1. 运行主机：香港服务器，已部署1Panel v2，openresty容器名称固定为 `openresty`。
2. 依赖工具：`sftp`、`docker`，系统默认自带。
3. 网络：香港服务器可以连通阿里云服务器 `115.29.215.239:1125`，**支持sftp免密登录（密钥登录）**。
> ⚠️必须配置SSH密钥免密，脚本没有交互输入密码逻辑，密码方式执行会卡住。
4. 阿里云侧：证书输出路径 `/opt/1panel/ssl‑helper/` 存放 `fullchain.pem`、`privkey.pem`。

## 部署步骤
### 1、存放脚本
```bash
mkdir -p /opt/1panel/ssl_sync
# 将脚本保存至 /opt/1panel/ssl_sync/pull_1panel_ssl.sh
```

### 2、赋予可执行权限
```bash
chmod +x /opt/1panel/ssl_sync/pull_1panel_ssl.sh
```

### 3、配置免密SFTP访问（关键）

香港服务器root生成ssh密钥，把公钥添加到阿里云服务器 root 账号的 ~/.ssh/authorized_keys ，保证执行：

```bash
sftp -P 1125 root@115.29.215.239
```

可以直接连上，不需要输入密码。


### 4、手动测试运行

```bash
/opt/1panel/ssl_sync/pull_1panel_ssl.sh
```

正常成功输出示例

```plaintext
Connected to 115.29.215.239.
sftp> get ...
Tue Sep  1 00:47:28 CST 2026 更新站点：calendar.one.xuechun.vip
Tue Sep  1 00:47:28 CST 2026 更新站点：openlist.one.xuechun.vip
Tue Sep  1 00:47:29 CST 2026 检测到openresty容器: openresty
Tue Sep  1 00:47:29 CST 2026 openresty 平滑重载完成
Tue Sep  1 00:47:29 CST 2026 证书更新流程结束
```

### 5、配置定时任务 crontab

可以利用s1panel的定时任务功能。

 
## 配置区参数说明（脚本头部）
 
```bash
ALIYUN_SSH_HOST="115.29.215.239"     #阿里云服务器IP
ALIYUN_SSH_PORT="1125"               #阿里云SSH端口
ALIYUN_SSH_USER="root"               #阿里云SSH用户名
ALI_FULLCHAIN="/opt/1panel/ssl-helper/fullchain.pem" #阿里云证书公钥路径
ALI_PRIVKEY="/opt/1panel/ssl-helper/privkey.pem"     #阿里云证书私钥路径

LOC_FULLCHAIN="/tmp/pull_fullchain.pem" #香港本地临时公钥
LOC_PRIVKEY="/tmp/pull_privkey.pem"     #香港本地临时私钥

SITE_ROOT="/opt/1panel/www/sites"       #1Panel站点根目录，一般无需修改
SUFFIX_MATCH="xuechun.vip"              #只处理以此结尾的站点文件夹
```
 
## 返回状态说明
 
1. ERROR：从阿里云下载证书失败 
 
sftp拉取证书失败，检查网络、ssh免密、阿里云文件路径是否存在。脚本直接exit退出，不会更新任何站点。
 
2. WARN：未找到运行的openresty容器，证书文件已替换，请手动重载服务 

docker没有找到名为openresty运行容器。磁盘证书已经全部更新，需要手动执行重载：

```bash
docker exec openresty openresty -s reload
```
 
3. ERROR：openresty配置语法错误，放弃重载 
 
nginx配置语法校验失败，禁止重载防止网站瘫痪，脚本直接退出。需要排查1Panel站点nginx配置错误。
 
验证证书是否生效
 
```bash
openssl s_client -connect openlist.one.xuechun.vip:443
```
 
查看输出里面证书有效期时间，确认是最新证书。
 
## 重要注意事项
 
1. 1Panel网页面板证书列表不会同步更新，属于预期行为；浏览器HTTPS读取磁盘pem文件不受影响。

2. 如果修改站点域名，站点文件夹名称后缀必须是 xuechun.vip 脚本才会处理。
3. 脚本依赖容器名称固定为  openresty ；如果重装1Panel改变容器名字，脚本会告警。
4. 私钥会短暂存放在  /tmp ，脚本结束自动清理临时文件。
5. 阿里云服务器需要保证证书文件持续更新（acme等签发程序），本脚本只负责拉取同步，不负责签发证书。
 
## 故障排查常用命令
 
```bash
#查看正在运行docker容器，确认openresty状态
docker ps

#手动测试openresty语法校验
docker exec openresty openresty -t

#手动平滑重载openresty
docker exec openresty openresty -s reload

#查看脚本运行日志
tail -n 100 /var/log/xuechun_ssl.log
```