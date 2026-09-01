# sync-1panel-ssl

## 使用说明
用途：将本地 `fullchain.pem`、`privkey.pem` 证书，批量上传更新到多台 1Panel 面板的 SSL 证书，支持**失败自动重试**，单个站点失败不会中断整体流程。
工作模式：使用 1Panel API `paste` 模式，直接把证书文本通过 HTTP 请求上传，不需要证书文件预先存放在远端 1Panel 服务器。
> 依赖环境：Linux，系统必须预先安装 `jq`；`md5sum`、`curl` 系统自带。

### 用法：
```bash
./script.sh                 # 使用脚本文件所在目录 fullchain.pem privkey.pem
./script.sh /opt/xxx/ssl    # 指定证书目录
```

### 新增站点：

复制一份【单个站点调用块】修改内部参数即可
```bash
# 格式： run_with_retry 最大重试次数 间隔秒数 upload_one_site 面板地址 API密钥 ssl_id 描述
run_with_retry 3 2 upload_one_site "https://mson.bxxxt.com" "u0...uXM" "5" "aliyun"
# run_with_retry 3 2 upload_one_site "https://xxx" "secret" "22" "hk‑site"
```

## 脚本特性

1. **多站点支持**：在脚本底部复制调用行即可新增站点，无需外部配置文件。
2. **失败重试机制**：每个站点可独立配置最大重试次数、失败等待间隔；网络抖动时自动重试。
3. **容错隔离**：某一个站点多次重试仍然失败，只会打印错误日志，**不会终止脚本，继续执行剩余站点**。
4. **自动路径处理**：自动解析脚本软链接，获取脚本真实所在目录。
5. **命令行参数**：支持传入证书目录参数；不传参默认读取脚本同目录证书文件。
6. **日志带时间戳**，便于排查定时任务运行问题。
7. **前置校验**：运行前检查证书文件是否存在、jq 工具是否安装，缺失直接报错退出。

## API 签名规则

1Panel 鉴权 Token 生成规则：
`TOKEN = md5(字符串"1panel" + API_SECRET + 当前Unix时间戳)`

> 
> ⚠️每次请求会生成全新时间戳与 Token，重试时每次都会重新生成签名。

## 使用方法

### 1、赋予执行权限

```
chmod +x sync-1panel-ssl.sh
```

### 2、配置站点

编辑脚本，找到脚本末尾站点配置区域：

```
# 格式： run_with_retry 最大重试次数 间隔秒数 upload_one_site 面板地址 API密钥 ssl_id 描述
run_with_retry 3 2 upload_one_site "shturl.cc/KUbDA5iQomuyH" "u0105.....RKtuXM" "5" "aliyun"
```

参数释义：

- `3`：最大重试次数（初次执行不算重试，失败最多重试 3 次）
- `2`：失败后休眠等待秒数
- `面板地址`：1Panel 面板网址，末尾**不要加斜杠**
- `API密钥`：1Panel 面板 API 密钥
- `ssl_id`：远端 1Panel 内 SSL 证书的 ID 编号（数字）
- `描述`：证书备注描述，会自动追加当前时间写入远端证书描述字段

> 
> 新增站点：直接复制整行，修改后面 4 个业务参数即可。

### 3、运行脚本

#### 方式 1：证书文件放在脚本同一目录

```
./sync-1panel-ssl.sh
```

#### 方式 2：指定证书所在目录（例如 acme 输出目录）

```
./sync-1panel-ssl.sh /etc/acme.sh/example.com
```
