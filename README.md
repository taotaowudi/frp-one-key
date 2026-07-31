# 🚀 FRP Manager 一体化管理脚本
一款适配 systemd amd64 架构的 FRP 全自动运维脚本，支持 **一键安装 / 版本升级 / 彻底卸载**，内置多Github加速代理、防火墙自动管理、交互式配置、Web面板、隧道批量配置、执行完毕自删脚本等功能。

## 一、脚本特性
### 核心能力
1. 双端支持：frpc客户端 / frps服务端 交互式安装
2. 自动版本拉取：多Github API加速源轮询，网络异常自动兜底固定版本
3. 多线路下载：ghproxy/镜像分流下载FRP二进制，内置wget带进度下载
4. 防火墙自动化
   - 安装时自动检测端口占用，输出对应放行命令
   - 卸载自动清理` ufw / firewalld 7000/7400/7500` 默认端口规则
5. `systemd `完整托管
   - 自动生成服务单元文件，配置重启策略、文件句柄上限
   - 提供启停/开机自启/日志查看全套操作指引
6. 交互式可视化配置
   - Web管理面板（自定义地址、端口、账号密码）
   - frpc批量添加多条`TCP/UDP/HTTP/STCP`隧道代理
7. 安全优化
   - 配置文件权限锁定 600，仅`root`可读
   - 卸载拦截系统高危目录，防止误删系统文件
8. 便捷附加功能
   - 升级自动备份旧二进制，提供一键回滚命令
   - 脚本执行完成自动删除自身，不残留临时文件
   - Ctrl+C中断自动清理临时压缩包/临时目录
9. 全发行版兼容
   - `Debian/Ubuntu/apt`、`CentOS/Rocky/dnf/yum`
   - 自动安装依赖`(curl/wget/jq)`
10. 本脚本依赖`frp`项目，感谢项目作者，链接`https://github.com/fatedier/frp`

### 系统限制
- 仅支持 `amd64(x86_64)` 架构
- 仅支持带 `systemd` 的 Linux 系统（主流云服务器均适配）
- 必须使用 `root / sudo `权限运行

## 二、快速使用教程
### 1. 国内服务器使用
```bash
wget https://gh-proxy.com/https://raw.githubusercontent.com/taotaowudi/frp-one-key/main/frp_manager.sh -O frp_manager.sh && chmod +x frp_manager.sh && ./frp_manager.sh
```
### 2. 国外服务器使用
```bash
wget https://raw.githubusercontent.com/taotaowudi/frp-one-key/main/frp_manager.sh -O frp_manager.sh && chmod +x frp_manager.sh && ./frp_manager.sh
```
### 3. 菜单功能说明
运行后会弹出功能选择菜单：
1. 全新安装 `frpc / frps`
   - 自定义安装目录（默认 `/opt/frp`）
   - 交互式填写Web面板、FRP认证Token、服务端地址/端口
   - frpc模式可批量添加多条隧道代理
   - 自动下载对应版本二进制、生成toml配置、创建systemd服务
2. 升级`frp`（保留原有全部配置）
   - 自动拉取最新版本，备份旧程序文件
   - 替换二进制并重启服务，附带回滚方案
3. 卸载`frpc / frps`
   - 停止并禁用`systemd`服务，查杀残留进程
   - 自动清理本地防火墙放行端口
   - 删除服务单元、程序目录、临时/日志残留文件
   - 高危目录拦截保护，防止误删系统根目录
### 4. toml配置说明
本脚本将引导配置最简单的`toml`
```bash frpc客户端
serverAddr = "1.1.1.1"          #frps服务器地址
serverPort = 7000               #frps服务器端口
auth.token = "111"              #token
webServer.addr = "0.0.0.0"      #web管理界面监听地址，如无特殊需求，保持默认即可
webServer.port = 7400           #web管理界面端口
webServer.user = "111"          #web管理界面用户名
webServer.password = "111"      #web管理界面密码
[[proxies]]                     #代理隧道1
name = "ssh"                    #代理名称
type = "tcp"                    #代理类型`(tcp/udp/http/https/stcp)`
localIP = "127.0.0.1"           #代理地址，默认local
localPort = 22                  #代理端口
remotePort = 10022              #远程`（frps）`端口,如不设则frps将自动分配端口
```
```bash frps服务端端
bindAddr = "0.0.0.0"            #frps server监听地址，默认监听所有地址，如无特殊需求，保持默认即可
bindPort = 7000                 #frps server端口，frpc填入此端口才能建立隧道连接，默认
auth.token = "111"              #token，frpc填入此鉴权密钥才能建立隧道连接
webServer.addr = "0.0.0.0"      #web管理界面监听地址，如无特殊需求，保持默认即可
webServer.port = 7500           #web管理界面端口
webServer.user = "111"          #web管理界面用户名
webServer.password = "111"      #web管理界面密码
```
详细toml配置请参见：`https://github.com/fatedier/frp/blob/dev/README.md`
修改配置执行```systemctl restart frps.service```

## 三、目录结构（默认安装路径 /opt/frp）
```
/opt/frp
├── bin/
│   ├── frpc       # 客户端二进制
│   └── frps       # 服务端二进制
└── conf/
    ├── frpc.toml  # 客户端配置文件（权限600）
    └── frps.toml  # 服务端配置文件（权限600）
```
systemd 服务文件路径：
```
/etc/systemd/system/frpc.service
/etc/systemd/system/frps.service
```
## 四、常用运维命令
### 通用服务操作
```
# 启动服务
systemctl start frpc.service
systemctl start frps.service

# 设置开机自启
systemctl enable frpc.service
systemctl enable frps.service

# 查看运行状态
systemctl status frpc.service

# 修改配置后重启
systemctl restart frpc.service

# 实时滚动查看运行日志
journalctl -u frpc.service -f

# 停止服务
systemctl stop frpc.service
```
### 防火墙放行参考
#### ufw (Debian/Ubuntu)
```
ufw allow 7000/tcp
ufw allow 7400/tcp
ufw allow 7500/tcp
ufw reload
```
#### firewalld (CentOS/Rocky)
```
firewall-cmd --add-port=7000/tcp --permanent
firewall-cmd --add-port=7400/tcp --permanent
firewall-cmd --add-port=7500/tcp --permanent
firewall-cmd --reload
```
> 重要：云服务器除本地防火墙外，需前往厂商控制台安全组放行对应端口

## 五、升级回滚方案
升级时脚本会自动备份旧二进制文件，格式：
frpc.bak.20260730_153000

回滚示例命令：
```
mv /opt/frp/bin/frpc.bak.20260730_153000 /opt/frp/bin/frpc && systemctl restart frpc.service
```
## 六、卸载注意事项
1. 卸载流程会自动清理本地防火墙`7000/7400/7500`端口规则，但**不会修改云服务器安全组**，需手动关闭对应端口；
2. 卸载时可选择保留/删除 `/opt/frp `配置目录；
3. 脚本会自动清理 `/tmp、/var/log` 下frp相关临时文件与日志；
4. 卸载完成后可执行以下命令校验无残留服务：
```systemctl list-unit-files | grep frp```

## 七、常见问题
### 1. 提示缺少 curl/wget/jq
脚本会自动检测缺失依赖，输入y一键自动安装；拒绝则输出对应系统安装命令手动操作。

### 2. Github API/下载地址全部连接失败
脚本自动切换兜底固定版本 `0.70.1`，后续可手动更换服务器网络重新执行升级功能拉取最新版。

### 3. 端口占用报错
脚本内置ss端口占用检测，若提示端口被占用，更换Web面板端口、FRP通信端口或隧道远程端口即可。

### 4. 脚本运行完自动消失
脚本内置自删除逻辑，执行完安装/升级/卸载后会自动删除自身文件，如需留存请复制一份再运行。

### 5. 客户端无法连接服务端
   - 核对 `serverAddr`、`serverPort`、`token` 和 `frps` 完全一致
   - 检查服务端防火墙/云安全组放行7000通信端口
   - 确认frps服务正常运行 ```systemctl status frps.service```
### 6. Web面板打不开
   - 核对面板端口未被占用
   - 防火墙放行面板端口
### 7. 隧道无法访问
   - 检查`remotePort`在服务端防火墙放行
   - 本地`localIP`、`localPort`程序正常运行
   - 查看日志 ```journalctl -u frpc.service -f```定位错误

## 八、License
MIT License
可自由修改、分发、商用，保留原脚本头部注释信息即可。
