#!/bin/bash
# FRP Manager 一体化脚本 安装｜升级｜卸载 amd64 systemd
# 已增强：依赖自动安装、完整web面板交互、frpc批量代理交互式创建
set -euo pipefail
# 捕获Ctrl+C清理临时文件
trap '[[ -n "${TMP_TAR:-}" && -f "${TMP_TAR}" ]] && rm -f "${TMP_TAR}"; [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"; echo -e "\n${YELLOW}[提示] 已清理临时文件，脚本退出${NC}"; exit 1' SIGINT SIGTERM

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 全局常量 ==========
ARCH="amd64"
FALLBACK_FR_VERSION="0.70.1"
GH_API="https://api.github.com/repos/fatedier/frp/releases/latest"
GH_API_PROXY="https://ghproxy.com/${GH_API}"

# ========== 公共函数：依赖检查 + 自动安装 ==========
check_dependencies() {
    local missing=()
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    if ! command -v wget &> /dev/null; then
        missing+=("wget")
    fi
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    if ! command -v systemctl &> /dev/null; then
        echo -e "${RED}[错误] 当前系统不支持 systemd，脚本无法运行！${NC}"
        exit 1
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}[校验] 所有依赖已就绪${NC}"
        return 0
    fi

    echo -e "${YELLOW}[警告] 缺失依赖组件：${missing[*]}${NC}"
    read -p "是否自动安装缺失依赖？[y/n] " INSTALL_DEP
    if [[ "${INSTALL_DEP,,}" != "y" ]]; then
        echo -e "${BLUE}Debian/Ubuntu：apt update && apt install curl wget jq -y${NC}"
        echo -e "${BLUE}CentOS/Rocky：yum install curl wget jq -y${NC}"
        exit 1
    fi

    # 判断系统包管理器安装
    if command -v apt &> /dev/null; then
        apt update && apt install curl wget jq -y
    elif command -v yum &> /dev/null; then
        yum install curl wget jq -y
    elif command -v dnf &> /dev/null; then
        dnf install curl wget jq -y
    else
        echo -e "${RED}[错误] 无法识别系统包管理器，请手动安装 curl wget jq${NC}"
        exit 1
    fi
    echo -e "${GREEN}[完成] 依赖安装完毕，继续执行脚本${NC}"
}

# ========== 公共函数：拉取最新版本 ==========
get_latest_frp_version() {
    echo -e "${BLUE}\n正在获取FRP最新版本号...${NC}"
    local VER=""
    # 多套国内镜像API兜底，按顺序轮询
    local API_URLS=(
	    "${GH_API}"
		"https://gh-proxy.org/${GH_API}"
        "https://ghproxy.net/${GH_API}"
        "${GH_API_PROXY}"
    )
    local retry_times=2

    for url in "${API_URLS[@]}"; do
        echo -e "${YELLOW}尝试接口：${url}${NC}"
        local resp=""
        # 单接口重试2次，超时15s
        for ((r=0; r < retry_times; r++)); do
            set +e
            resp=$(curl -fsSL --max-time 15 "${url}" 2>/tmp/frp_api_err.log)
            set -e
            if [[ -n "${resp}" ]]; then
                break
            fi
            # 读取curl报错并打印
            err_msg=$(cat /tmp/frp_api_err.log)
            echo -e "${RED}接口请求失败：${err_msg}，等待1秒重试${NC}"
            sleep 1
        done
        rm -f /tmp/frp_api_err.log

        if [[ -z "${resp}" ]]; then
            echo -e "${YELLOW}当前接口完全无法访问，切换下一个源${NC}"
            continue
        fi

        # 解析版本
        if command -v jq &> /dev/null; then
            VER=$(echo "${resp}" | jq -r '.tag_name' | sed 's/^v//')
        else
            VER=$(echo "${resp}" | sed -nE 's/.*"tag_name":"v([0-9.]+)".*/\1/p' | head -n1)
        fi

        if [[ -n "${VER}" && "${VER}" != "null" ]]; then
            break
        fi
        echo -e "${YELLOW}接口返回数据解析无有效版本，切换下一个源${NC}"
    done

    if [[ -z "${VER}" || "${VER}" == "null" ]]; then
        echo -e "${RED}[严重警告] 所有镜像接口均连接失败/解析失败，网络无法访问Github Release接口${NC}"
        echo -e "${YELLOW}当前将使用兜底固定版本 v${FALLBACK_FR_VERSION}，如需最新版请检查服务器网络或切换网络环境${NC}"
        FRP_VERSION="${FALLBACK_FR_VERSION}"
    else
        FRP_VERSION="${VER}"
        echo -e "${GREEN}✅ 检测到最新frp版本：v${FRP_VERSION}${NC}"
    fi
}

# ========== 公共函数：下载frp二进制 ==========
# ========== 公共函数：下载frp二进制 ==========
download_frp_bin() {
    local BIN_NAME="$1"
    TMP_TAR=$(mktemp)
    TMP_DIR=$(mktemp -d)
    local raw_url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
    # 多下载源轮询
    local DL_URLS=(
	    "${raw_url}"
        "https://gh-proxy.org/${raw_url}"
        "https://ghproxy.net/${raw_url}"
        "https://ghp.keleyaa.com/${raw_url}"
        "${raw_url}"
    )
    local dl_ok=false

    echo -e "${GREEN}\n开始下载 FRP v${FRP_VERSION} linux_${ARCH}${NC}"
    for dl in "${DL_URLS[@]}"; do
        echo -e "${BLUE}尝试下载地址：${dl}${NC}"
        if wget -q --timeout=15 "${dl}" -O "${TMP_TAR}"; then
            echo -e "${GREEN}当前地址下载成功${NC}"
            dl_ok=true
            break
        fi
        echo -e "${YELLOW}下载超时/连接重置，切换下一个下载源${NC}"
    done

    if [[ "${dl_ok}" != true ]]; then
        echo -e "${RED}[错误] 所有下载地址均无法连接，终止安装${NC}"
        rm -rf "${TMP_TAR}" "${TMP_DIR}"
        exit 1
    fi

    tar -zxf "${TMP_TAR}" -C "${TMP_DIR}"
    cp "${TMP_DIR}/frp_${FRP_VERSION}_linux_${ARCH}/${BIN_NAME}" "${TARGET_BIN}"
    chmod +x "${TARGET_BIN}"
    rm -rf "${TMP_TAR}" "${TMP_DIR}"
    unset TMP_TAR TMP_DIR
    echo -e "${GREEN}二进制文件就绪：${TARGET_BIN}${NC}"
}

# ========== 公共函数：端口检测与防火墙提示 ==========
check_port_firewall() {
    local PORT=$1
    echo -e "${BLUE}\n[端口检测] 检查端口 ${PORT} 占用情况${NC}"
    if command -v ss &> /dev/null; then
        if ss -tulpn | grep ":${PORT}" &> /dev/null; then
            echo -e "${RED}[警告] 端口${PORT}已经被其他程序占用！请更换端口${NC}"
        else
            echo -e "${GREEN}[正常] 端口${PORT}当前未被占用${NC}"
        fi
    else
        echo -e "${YELLOW}[提示] 未找到ss命令，跳过端口占用检测${NC}"
    fi
    echo -e "${YELLOW}[防火墙放行提示] 请在防火墙开放端口 ${PORT}"
    if command -v ufw &> /dev/null; then
        echo "ufw放行命令：ufw allow ${PORT}/tcp"
    elif command -v firewall-cmd &> /dev/null; then
        echo "firewalld放行命令：firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload"
    else
        echo "当前未检测到ufw/firewalld，云服务器务必放行云端安全组端口！"
    fi
}

# ========== 交互式填写公共Web面板配置 ==========
input_web_config() {
    echo -e "\n${BLUE}===== 配置Web管理面板 =====${NC}"
    read -p "web面板监听地址(默认0.0.0.0)：" WEB_ADDR
    WEB_ADDR=${WEB_ADDR:-0.0.0.0}
    read -p "web面板端口(默认7500)：" WEB_PORT
    WEB_PORT=${WEB_PORT:-7500}
    check_port_firewall "${WEB_PORT}"
    read -p "web面板用户名：" WEB_USER
    read -s -p "web面板密码：" WEB_PWD
    echo ""
}

# ========== frpc 批量交互式添加代理 ==========
input_frpc_proxies() {
    echo -e "\n${BLUE}===== 开始配置隧道代理 =====${NC}"
    local proxy_block=""
    local add_more="y"
    while [[ "${add_more,,}" == "y" ]]; do
        echo -e "\n${YELLOW}--- 新增一条代理隧道 ---${NC}"
        read -p "隧道名称name：" P_NAME
        read -p "代理类型type(tcp/udp/http/https/stcp)：" P_TYPE
        read -p "本地地址localIP(默认127.0.0.1)：" P_LOCAL_IP
        P_LOCAL_IP=${P_LOCAL_IP:-127.0.0.1}
        read -p "本地端口localPort：" P_LOCAL_PORT
        read -p "远程端口remotePort：" P_REMOTE_PORT
        check_port_firewall "${P_REMOTE_PORT}"

        # 拼接代理块
        proxy_block+="[[proxies]]
name = \"${P_NAME}\"
type = \"${P_TYPE}\"
localIP = \"${P_LOCAL_IP}\"
localPort = ${P_LOCAL_PORT}
remotePort = ${P_REMOTE_PORT}

"
        read -p "是否继续添加下一条隧道？[y/n] " add_more
    done
    echo "${proxy_block}"
}

# ========== 功能1：全新安装 ==========
func_install() {
    echo -e "${GREEN}===== 进入全新安装流程 =====${NC}"
    read -p "请选择安装类型 [1=frpc客户端 | 2=frps服务端]：" TYPE
    if [[ "$TYPE" == "1" ]]; then
        BIN_NAME="frpc"
        SERVICE_NAME="frpc.service"
    elif [[ "$TYPE" == "2" ]]; then
        BIN_NAME="frps"
        SERVICE_NAME="frps.service"
    else
        echo -e "${RED}[错误] 只能输入数字1或2！${NC}"
        exit 1
    fi

    read -p "请输入FRP安装目录（默认 /opt/frp，直接回车使用默认）：" INSTALL_PATH
    [[ -z "$INSTALL_PATH" ]] && INSTALL_PATH="/opt/frp"

    # 1. Web面板配置
    input_web_config

    # 2. FRP基础连接配置
    echo -e "\n${BLUE}===== FRP基础连接配置 =====${NC}"
    if [[ "${BIN_NAME}" == "frpc" ]]; then
        read -p "FRP服务端地址serverAddr：" SERVER_ADDR
    else
        read -p "服务端绑定监听地址bindAddr(默认0.0.0.0)：" SERVER_ADDR
        SERVER_ADDR=${SERVER_ADDR:-0.0.0.0}
    fi
    read -p "FRP通信端口serverPort/bindPort（默认7000，回车默认）：" SERVER_PORT
    [[ -z "$SERVER_PORT" ]] && SERVER_PORT="7000"
    check_port_firewall "${SERVER_PORT}"
    read -s -p "FRP认证Token：" TOKEN
    echo ""
    read -p "是否启用TLS加密 [y/n，默认n]：" ENABLE_TLS
    ENABLE_TLS=${ENABLE_TLS:-n}

    mkdir -p "${INSTALL_PATH}/bin" "${INSTALL_PATH}/conf"
    CONF_FILE="${INSTALL_PATH}/conf/${BIN_NAME}.toml"
    TARGET_BIN="${INSTALL_PATH}/bin/${BIN_NAME}"

    get_latest_frp_version
    download_frp_bin "${BIN_NAME}"

    # 生成TOML配置
    > "${CONF_FILE}"
    if [[ "${BIN_NAME}" == "frpc" ]]; then
        cat >> "${CONF_FILE}" <<EOF
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}
auth.token = "${TOKEN}"
tlsEnable = $( [[ "${ENABLE_TLS,,}" == "y" ]] && echo true || echo false )

webServer.addr = "${WEB_ADDR}"
webServer.port = ${WEB_PORT}
webServer.user = "${WEB_USER}"
webServer.password = "${WEB_PWD}"
EOF
        # 交互式追加所有代理
        proxy_content=$(input_frpc_proxies)
        echo -e "${proxy_content}" >> "${CONF_FILE}"
    else
        cat >> "${CONF_FILE}" <<EOF
bindAddr = "${SERVER_ADDR}"
bindPort = ${SERVER_PORT}
auth.token = "${TOKEN}"
tlsEnable = $( [[ "${ENABLE_TLS,,}" == "y" ]] && echo true || echo false )

webServer.addr = "${WEB_ADDR}"
webServer.port = ${WEB_PORT}
webServer.user = "${WEB_USER}"
webServer.password = "${WEB_PWD}"

# vhostHTTPPort = 8080
# vhostHTTPSPort = 8443
EOF
    fi

    # 密钥配置文件权限加固
    chmod 600 "${CONF_FILE}"
    echo -e "${GREEN}[安全] 已设置配置文件权限600，仅root可读${NC}"

    echo -e "${YELLOW}\n配置文件已生成，选择操作：${NC}"
    echo "回车直接跳过；输入 edit 使用nano编辑toml"
    read -p "操作：" EDIT_OPT
    if [[ "${EDIT_OPT}" == "edit" ]]; then
        if command -v nano &> /dev/null; then
            nano "${CONF_FILE}"
        else
            echo -e "${RED}未安装nano，请手动编辑：${CONF_FILE}${NC}"
        fi
    fi

    # 创建systemd服务
    SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
    cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=FRP ${BIN_NAME} Service
After=network.target syslog.target
Wants=network.target
[Service]
Type=simple
ExecStart=${TARGET_BIN} -c ${CONF_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo -e "${GREEN}\n=============================================${NC}"
    echo -e "✅ ${BIN_NAME} v${FRP_VERSION} 安装完成！"
    echo -e "安装目录：${INSTALL_PATH}"
    echo -e "配置文件：${CONF_FILE}"
    echo -e "服务名称：${SERVICE_NAME}"
    echo -e "${GREEN}常用命令：${NC}"
    echo "systemctl start ${SERVICE_NAME}"
    echo "systemctl enable ${SERVICE_NAME}"
    echo "systemctl status ${SERVICE_NAME}"
    echo "journalctl -u ${SERVICE_NAME} -f"
    echo -e "${GREEN}=============================================${NC}"
}

# ========== 功能2：升级frp ==========
func_update() {
    echo -e "${GREEN}===== 进入FRP升级流程（保留配置） =====${NC}"
    read -p "升级 [1=frpc客户端 | 2=frps服务端]：" TYPE
    if [[ "$TYPE" == "1" ]]; then
        BIN_NAME="frpc"
        SERVICE_NAME="frpc.service"
    elif [[ "$TYPE" == "2" ]]; then
        BIN_NAME="frps"
        SERVICE_NAME="frps.service"
    else
        echo -e "${RED}输入错误！${NC}"
        exit 1
    fi
    read -p "输入FRP安装目录（默认 /opt/frp，回车默认）：" INSTALL_PATH
    [[ -z "$INSTALL_PATH" ]] && INSTALL_PATH="/opt/frp"
    TARGET_BIN="${INSTALL_PATH}/bin/${BIN_NAME}"
    if [[ ! -f "${TARGET_BIN}" ]]; then
        echo -e "${RED}[错误] 找不到程序 ${TARGET_BIN}，目录错误！${NC}"
        exit 1
    fi
    get_latest_frp_version
    BACKUP_BIN="${TARGET_BIN}.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "${BLUE}备份旧二进制至：${BACKUP_BIN}${NC}"
    cp "${TARGET_BIN}" "${BACKUP_BIN}"
    download_frp_bin "${BIN_NAME}"
    echo -e "${BLUE}重启服务 ${SERVICE_NAME}${NC}"
    systemctl stop "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"
    echo -e "${GREEN}\n✅ ${BIN_NAME}升级完成！${NC}"
    echo "备份文件：${BACKUP_BIN}"
    echo "回滚命令示例：mv ${BACKUP_BIN} ${TARGET_BIN} && systemctl restart ${SERVICE_NAME}"
}

# ========== 功能3：卸载frp ==========
func_uninstall() {
    echo -e "${RED}===== 进入FRP卸载流程 =====${NC}"
    read -p "卸载 [1=frpc客户端 | 2=frps服务端]：" TYPE
    if [[ "$TYPE" == "1" ]]; then
        SERVICE_NAME="frpc.service"
    elif [[ "$TYPE" == "2" ]]; then
        SERVICE_NAME="frps.service"
    else
        echo -e "${RED}输入错误！${NC}"
        exit 1
    fi
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}"
    systemctl daemon-reload
    read -p "输入FRP安装目录（例 /opt/frp），确认删除目录：" DIR
    if [[ -d "${DIR}" ]]; then
        read -p "确认彻底删除目录 ${DIR} 所有文件？[y/n] " DEL_CONFIRM
        if [[ "${DEL_CONFIRM,,}" == "y" ]]; then
            rm -rf "${DIR}"
            echo -e "${GREEN}目录 ${DIR} 已删除${NC}"
        else
            echo -e "${YELLOW}已取消删除目录${NC}"
        fi
    fi
    echo -e "${GREEN}卸载完成${NC}"
}

# ========== 主菜单 ==========
main() {
    check_dependencies
    echo -e "${GREEN}=============================================${NC}"
    echo -e "          FRP 一体化管理脚本 amd64 systemd"
    echo -e "${GREEN}=============================================${NC}"
    echo "1) 全新安装 frpc / frps（交互式完整配置）"
    echo "2) 升级 frp 二进制（保留配置）"
    echo "3) 卸载 frpc / frps（带二次确认）"
    echo -e "${GREEN}=============================================${NC}"
    read -p "请选择功能编号(1/2/3)：" MENU_OPT
    case "${MENU_OPT}" in
        1) func_install ;;
        2) func_update ;;
        3) func_uninstall ;;
        *) echo -e "${RED}无效选项，退出${NC}"; exit 1 ;;
    esac
}

# 启动入口
main