#!/usr/bin/env bash
# =============================================================================
#  IP 质量体检脚本 (IPv4 / IPv6)
#  - 检测本机出口 IP 的地理位置、运营商、ASN、IP 类型、原生 IP 判定
#  - 检测流媒体 & AI 服务解锁：TikTok / Disney+ / Netflix / YouTube /
#    Amazon Prime Video / Reddit / ChatGPT
#
#  用法：
#    bash ipcheck.sh        # 进入交互菜单
#    bash ipcheck.sh -4     # 只检测 IPv4
#    bash ipcheck.sh -6     # 只检测 IPv6
#
#  依赖：curl（以及支持 -P 的 grep，绝大多数 Linux 自带 GNU grep）
#
#  Windows PowerShell 上运行本 .sh 脚本，需要先安装 Git Bash 或 WSL，
#  例如在 WSL 里：  bash ipcheck.sh
# =============================================================================

# ------------------------------- 颜色定义 ---------------------------------
NC=$'\033[0m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'

# ------------------------------- 请求参数 ---------------------------------
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
UA_SEC_CH_UA='"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"'
CURL_OPTS="-s --max-time 12 --retry 2 --retry-max-time 20"
SCRIPT_VERSION="1.0"

# Disney+ 检测所需的固定请求体（内置，无需额外下载）
DISNEY_BEARER="ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84"
DISNEY_TOKEN_BODY='grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange&latitude=0&longitude=0&platform=browser&subject_token=DISNEYASSERTION&subject_token_type=urn%3Abamtech%3Aparams%3Aoauth%3Atoken-type%3Adevice'
DISNEY_GRAPHQL_BODY='{"query":"mutation refreshToken($input: RefreshTokenInput!) {\n            refreshToken(refreshToken: $input) {\n                activeSession {\n                    sessionId\n                }\n            }\n        }","variables":{"input":{"refreshToken":"ILOVEDISNEY"}}}'

# 用于“可复制”结果汇总
SUMMARY_LINES=()

# ------------------------------- 基础函数 ---------------------------------
check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}错误：未安装 curl，请先安装：apt install curl 或 yum install curl${NC}"
        exit 1
    fi
    if ! echo 'e' | grep -P 'e' >/dev/null 2>&1; then
        echo -e "${RED}错误：当前 grep 不支持 -P（Perl 正则），请安装完整版 grep。${NC}"
        exit 1
    fi
}

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}========== $1 ==========${NC}"
}

# 去除 ANSI 颜色码，保证“可复制”汇总为纯文本
strip_ansi() {
    echo -n "$1" | sed -e 's/\x1b\[[0-9;]*m//g'
}

# 按显示宽度补齐（中文/全角=2列，ASCII=1列）
pad() {
    local s="$1" target="$2"
    local w=0 i c b n
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        b=$(printf '%d' "'$c")
        if [ "$b" -gt 127 ]; then
            w=$((w+2))
        else
            w=$((w+1))
        fi
    done
    n=$((target - w))
    [ "$n" -lt 0 ] && n=0
    printf '%s' "$s"
    printf '%*s' "$n" ''
}

print_separator() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

# 打印一个键值对，并同时记录到“可复制”汇总
print_kv() {
    local name="$1" value="$2"
    printf "  ${BOLD}%s${NC}%s\n" "$(pad "$name" 18)" "$value"
    SUMMARY_LINES+=("  $(pad "$name" 18)  $(strip_ansi "$value")")
}

# 打印一条检测结果（带颜色），并记录到“可复制”汇总
print_line() {
    local name="$1" status="$2"
    local colored
    case "$status" in
        解锁*|Yes*)        colored="${GREEN}${status}${NC}" ;;
        仅自制剧*|即将支持*|仅网页*|仅App*|未检测到*|不支持*) colored="${YELLOW}${status}${NC}" ;;
        否*|No*)           colored="${RED}${status}${NC}" ;;
        *)                 colored="${RED}${status}${NC}" ;;
    esac
    printf "  ${BOLD}%-18s${NC}%s\n" "$name" "$colored"
    SUMMARY_LINES+=("  $(pad "$name" 18)  $status")
}

# 打印可复制的纯文本汇总
print_copy_summary() {
    echo ""
    echo -e "${BOLD}${CYAN}===== 结果汇总（纯文本，可直接复制）=====${NC}"
    printf '%s\n' "${SUMMARY_LINES[@]}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

# ------------------------------- 获取出口 IP ------------------------------
get_local_ip() {
    local ipflag="$1"
    if [ "$ipflag" == "-6" ]; then
        curl $CURL_OPTS $ipflag -s "https://api64.ipify.org"
    else
        curl $CURL_OPTS $ipflag -s "https://api.ipify.org"
    fi
}

# 诊断网络不通的具体原因（返回简短中文说明）
net_reason() {
    local url="$1" ipflag="$2"
    local err code
    err=$(curl --max-time 12 $ipflag -sS -o /dev/null "$url" 2>&1)
    code=$?
    case "$code" in
        0)  echo "可达" ;;
        6)  echo "DNS解析失败" ;;
        7)  echo "无法建立连接(端口不通/无路由)" ;;
        28) echo "连接超时" ;;
        35) echo "SSL/TLS握手失败" ;;
        *)  echo "${err:-未知}" ;;
    esac
}

# 生成统一的网络失败说明（含具体地址 + 原因）
net_fail() {
    local url="$1" ipflag="$2"
    local proto="IPv4"
    [ "$ipflag" == "-6" ] && proto="IPv6"
    echo "失败(网络连接): 无法访问 ${url} [$proto $(net_reason "$url" "$ipflag")]"
}

# ------------------------------- IP 信息检测 ------------------------------
check_ip_info() {
    local ip="$1" ipflag="$2"

    local who=$(curl $CURL_OPTS $ipflag -s "https://ipwho.is/$ip")
    local api=$(curl $CURL_OPTS $ipflag -s "http://ip-api.com/json/$ip?lang=zh-CN&fields=status,country,regionName,city,isp,org,asname,reverse,timezone,query")
    # ipapi.is：与 xykt/IPQuality 同源的风险库，用于判断机房/住宅/代理/VPN/Tor
    local iq=$(curl $CURL_OPTS $ipflag -s "https://api.ipapi.is/?q=$ip")

    local type=$(echo "$who"   | grep -oP '"type"\s*:\s*"\K[^"]+')
    local asn=$(echo "$who"    | grep -oP '"asn"\s*:\s*\K[0-9]+')
    local isp=$(echo "$who"    | grep -oP '"isp"\s*:\s*"\K[^"]+')
    local org=$(echo "$who"    | grep -oP '"org"\s*:\s*"\K[^"]+')
    local tz=$(echo "$who"     | grep -oP '"id"\s*:\s*"\K[^"]+' | head -n1)

    local country=$(echo "$api"     | grep -oP '"country"\s*:\s*"\K[^"]+')
    local regionName=$(echo "$api"  | grep -oP '"regionName"\s*:\s*"\K[^"]+')
    local city=$(echo "$api"        | grep -oP '"city"\s*:\s*"\K[^"]+')
    local asname=$(echo "$api"      | grep -oP '"asname"\s*:\s*"\K[^"]+')
    local reverse=$(echo "$api"     | grep -oP '"reverse"\s*:\s*"\K[^"]+')

    local is_tor=$(echo "$iq"     | grep -oP '"is_tor"\s*:\s*\K(true|false)')
    local is_vpn=$(echo "$iq"     | grep -oP '"is_vpn"\s*:\s*\K(true|false)')
    local is_proxy=$(echo "$iq"   | grep -oP '"is_proxy"\s*:\s*\K(true|false)')
    local is_dc=$(echo "$iq"      | grep -oP '"is_datacenter"\s*:\s*\K(true|false)')

    # IP 类型判定（ipapi.is，与 xykt 同源）
    local ip_type="未知"
    if [ "$is_tor" == "true" ]; then
        ip_type="Tor 出口节点"
    elif [ "$is_vpn" == "true" ]; then
        ip_type="VPN"
    elif [ "$is_proxy" == "true" ]; then
        ip_type="代理"
    elif [ "$is_dc" == "true" ]; then
        ip_type="机房/数据中心 (IDC)"
    else
        ip_type="住宅/家庭宽带"
    fi

    # 原生住宅IP 判定：机房/代理/VPN/Tor 任一为 true 即视为非原生
    local native="未知"
    if [ "$is_dc" == "true" ] || [ "$is_proxy" == "true" ] || [ "$is_vpn" == "true" ] || [ "$is_tor" == "true" ]; then
        native="${RED}否（机房/代理 IP）${NC}"
    else
        native="${GREEN}是（原生住宅 IP，非机房/代理）${NC}"
    fi

    local location=""
    [ -n "$country" ] && location="$country"
    [ -n "$regionName" ] && location="${location} / ${regionName}"
    [ -n "$city" ] && location="${location} / ${city}"

    print_kv "IP 地址"    "${BOLD}${ip}${NC} (${type:-未知})"
    print_kv "地理位置"    "${location:-未知}"
    print_kv "运营商 ISP"  "${isp:-${org:-未知}}"
    [ -n "$asn" ] && print_kv "ASN" "AS${asn}${asname:+ ($asname)}"
    [ -n "$reverse" ] && print_kv "反向解析" "$reverse"
    print_kv "IP 类型"    "$ip_type"
    print_kv "原生住宅IP"    "$native"
    [ -n "$tz" ] && print_kv "时区" "$tz"
}

# ------------------------------- 流媒体/AI 解锁检测 ------------------------
check_netflix() {
    local ipflag="$1"
    local r1=$(curl $CURL_OPTS $ipflag -fsL --user-agent "$UA_BROWSER" "https://www.netflix.com/title/81280792")
    local r2=$(curl $CURL_OPTS $ipflag -fsL --user-agent "$UA_BROWSER" "https://www.netflix.com/title/70143836")
    [ -z "$r1" ] || [ -z "$r2" ] && { echo "$(net_fail "https://www.netflix.com" "$ipflag")"; return; }

    local ohno1=$(echo "$r1" | grep 'Oh no!')
    local ohno2=$(echo "$r2" | grep 'Oh no!')
    if [ -n "$ohno1" ] && [ -n "$ohno2" ]; then
        echo "仅自制剧"
        return
    fi
    local region=$(echo "$r1" | sed -n 's/.*"id":"\([^"]*\)".*"countryName":"[^"]*".*/\1/p' | head -n1)
    [ -z "$region" ] && region=$(echo "$r1" | grep -oP '"countryName"\s*:\s*"\K[^"]+' | head -n1)
    if [ -n "$region" ]; then
        echo "解锁 (区域: ${region})"
    else
        echo "解锁"
    fi
}

check_disney() {
    local ipflag="$1"
    [ "$ipflag" == "-6" ] && { echo "不支持 IPv6"; return; }

    local devices=$(curl $CURL_OPTS $ipflag -s "https://disney.api.edge.bamgrid.com/devices" -X POST \
        -H "authorization: Bearer ${DISNEY_BEARER}" \
        -H "content-type: application/json; charset=UTF-8" \
        -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' \
        --user-agent "$UA_BROWSER")
    [ -z "$devices" ] && { echo "$(net_fail "https://disney.api.edge.bamgrid.com" "$ipflag")"; return; }
    echo "$devices" | grep -qi '403 ERROR' && { echo "否(IP 被封禁)"; return; }

    local assertion=$(echo "$devices" | grep -oP '"assertion"\s*:\s*"\K[^"]+')
    [ -z "$assertion" ] && { echo "失败(页面异常)"; return; }

    local token_body=$(echo "$DISNEY_TOKEN_BODY" | sed "s|DISNEYASSERTION|${assertion}|g")
    local token=$(curl $CURL_OPTS $ipflag -s "https://disney.api.edge.bamgrid.com/token" -X POST \
        -H "authorization: Bearer ${DISNEY_BEARER}" \
        -d "$token_body" \
        --user-agent "$UA_BROWSER")
    echo "$token" | grep -qi 'forbidden-location\|403 ERROR' && { echo "否(IP 被封禁)"; return; }

    local refresh=$(echo "$token" | grep -oP '"refresh_token"\s*:\s*"\K[^"]+')
    [ -z "$refresh" ] && { echo "失败(页面异常)"; return; }

    local graphql_body=$(echo "$DISNEY_GRAPHQL_BODY" | sed "s|ILOVEDISNEY|${refresh}|g")
    local result=$(curl $CURL_OPTS $ipflag -sL "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -X POST \
        -H "authorization: ${DISNEY_BEARER}" \
        -d "$graphql_body" \
        --user-agent "$UA_BROWSER")

    local region=$(echo "$result" | grep -oP '"countryCode"\s*:\s*"\K[^"]+')
    local supported=$(echo "$result" | grep -oP '"inSupportedLocation"\s*:\s*\K(false|true)')
    [ -z "$region" ] && { echo "否"; return; }
    [ "$region" == "JP" ] && { echo "解锁 (区域: JP)"; return; }
    [ "$supported" == "true" ] && { echo "解锁 (区域: ${region})"; return; }
    [ "$supported" == "false" ] && { echo "即将支持 (区域: ${region})"; return; }
    echo "失败(未知)"
}

check_youtube() {
    local ipflag="$1"
    local r=$(curl $CURL_OPTS $ipflag -sL "https://www.youtube.com/premium" \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "$UA_BROWSER")
    [ -z "$r" ] && { echo "$(net_fail "https://www.youtube.com/premium" "$ipflag")"; return; }
    echo "$r" | grep -q 'www.google.cn' && { echo "否 (Premium 不支持，区域: CN)"; return; }

    local region=$(echo "$r" | grep -oP '"INNERTUBE_CONTEXT_GL"\s*:\s*"\K[^"]+')
    echo "$r" | grep -qi 'Premium is not available in your country' && { echo "否 (Premium 不支持)"; return; }
    if echo "$r" | grep -qi 'ad-free'; then
        echo "解锁 (区域: ${region:-未知})"
    else
        echo "失败(页面异常)"
    fi
}

check_primevideo() {
    local ipflag="$1"
    [ "$ipflag" == "-6" ] && { echo "不支持 IPv6"; return; }

    local r=$(curl $CURL_OPTS $ipflag -sL "https://www.primevideo.com" --user-agent "$UA_BROWSER")
    [ -z "$r" ] && { echo "$(net_fail "https://www.primevideo.com" "$ipflag")"; return; }

    local blocked=$(echo "$r" | grep -i 'isServiceRestricted')
    local region=$(echo "$r" | grep -oP '"currentTerritory":"\K[^"]+' | head -n1)
    [ -n "$blocked" ] && { echo "否(服务不可用)"; return; }
    [ -n "$region" ] && { echo "解锁 (区域: ${region})"; return; }
    echo "失败(页面异常)"
}

check_tiktok() {
    local ipflag="$1"
    local r=$(curl $CURL_OPTS $ipflag -sL --user-agent "$UA_BROWSER" "https://www.tiktok.com/")
    [ -z "$r" ] && { echo "$(net_fail "https://www.tiktok.com/" "$ipflag")"; return; }

    local region=$(echo "$r" | grep -oP '"region"\s*:\s*"\K[^"]+' | head -n1)
    if [ -n "$region" ]; then
        echo "解锁 (区域: ${region})"
    else
        echo "未检测到区域(建议手动验证)"
    fi
}

check_reddit() {
    local ipflag="$1"
    [ "$ipflag" == "-6" ] && { echo "不支持 IPv6"; return; }

    local code=$(curl $CURL_OPTS $ipflag -fsL "https://www.reddit.com/" -w '%{http_code}' -o /dev/null --user-agent "$UA_BROWSER")
    case "$code" in
        200) echo "解锁" ;;
        403) echo "否" ;;
        000) echo "$(net_fail "https://www.reddit.com/" "$ipflag")" ;;
        *)   echo "失败($code)" ;;
    esac
}

check_chatgpt() {
    local ipflag="$1"
    local r1=$(curl $CURL_OPTS $ipflag -s "https://api.openai.com/compliance/cookie_requirements" \
        -H 'accept: */*' -H 'accept-language: en-US,en;q=0.9' \
        -H 'authorization: Bearer null' -H 'content-type: application/json' \
        -H 'origin: https://platform.openai.com' -H 'referer: https://platform.openai.com/' \
        -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' \
        -H 'sec-fetch-dest: empty' -H 'sec-fetch-mode: cors' -H 'sec-fetch-site: same-site' \
        --user-agent "$UA_BROWSER")
    local r2=$(curl $CURL_OPTS $ipflag -s "https://ios.chat.openai.com/" \
        -H "sec-ch-ua: ${UA_SEC_CH_UA}" -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' \
        --user-agent "$UA_BROWSER")
    local proto="IPv4"
    [ "$ipflag" == "-6" ] && proto="IPv6"

    if [ -z "$r1" ] && [ -z "$r2" ]; then
        echo "失败(网络连接): api.openai.com 与 ios.chat.openai.com 均无法访问"
        return
    fi
    if [ -z "$r1" ]; then
        echo "失败(网络连接): 无法访问 api.openai.com [$proto $(net_reason "https://api.openai.com" "$ipflag")]"
        return
    fi
    if [ -z "$r2" ]; then
        echo "失败(网络连接): 无法访问 ios.chat.openai.com [$proto $(net_reason "https://ios.chat.openai.com" "$ipflag")]"
        return
    fi

    local unsupported=$(echo "$r1" | grep -i 'unsupported_country')
    local vpn=$(echo "$r2" | grep -i 'VPN')
    if [ -z "$vpn" ] && [ -z "$unsupported" ]; then echo "解锁 (网页/App均可用)"; return; fi
    if [ -n "$vpn" ] && [ -n "$unsupported" ]; then echo "否 (网页/App均不可用)"; return; fi
    if [ -n "$vpn" ] && [ -z "$unsupported" ]; then echo "仅网页可用 (App不可用)"; return; fi
    if [ -z "$vpn" ] && [ -n "$unsupported" ]; then echo "仅App可用 (网页不可用)"; return; fi
    echo "失败(未知)"
}

# ------------------------------- 视频平台测速 ------------------------------
# 测单个平台延迟（TCP连接 / 首字节）
speed_latency() {
    local url="$1"
    local t=$(curl -4 -s -o /dev/null --max-time 10 -w '%{time_connect}|%{time_starttransfer}' "$url" 2>/dev/null)
    local c=$(echo "$t" | cut -d'|' -f1)
    local s=$(echo "$t" | cut -d'|' -f2)
    [ -z "$c" ] && c=0
    [ -z "$s" ] && s=0
    local cms=$(awk "BEGIN{printf \"%d\", $c*1000}")
    local sms=$(awk "BEGIN{printf \"%d\", $s*1000}")
    echo "连接 ${cms}ms / 首字节 ${sms}ms"
}

# 打印单平台测速结果（含测试链接）
speed_row() {
    local name="$1" url="$2"
    print_kv "$name" "${url}  $(speed_latency "$url")"
}

check_platform_speed() {
    SUMMARY_LINES=()
    print_header "视频平台测速（IPv4）"
    print_separator "下载速度 & 各平台延迟"

    local dl=$(curl -4 -s -o /dev/null --max-time 30 -w '%{speed_download}' "https://speed.cloudflare.com/__down?bytes=104857600" 2>/dev/null)
    [ -z "$dl" ] && dl=0
    local dl_mbps=$(awk "BEGIN{printf \"%.2f\", $dl*8/1000000}")
    print_kv "通用下载速度" "${dl_mbps} Mbps"

    echo ""
    print_separator "各平台延迟"
    speed_row "YouTube" "https://www.youtube.com"
    speed_row "X"       "https://x.com"
    speed_row "Telegram" "https://web.telegram.org"
    speed_row "Netflix" "https://www.netflix.com"
    speed_row "TikTok"  "https://www.tiktok.com"

    print_copy_summary
}

# ------------------------------- 主检测流程 -------------------------------
run_tests() {
    local ipflag="$1"
    local label="IPv4"
    [ "$ipflag" == "-6" ] && label="IPv6"

    SUMMARY_LINES=()
    local ip=$(get_local_ip "$ipflag")
    if [ -z "$ip" ]; then
        echo -e "${RED}无法获取 ${label} 出口地址，可能本机不支持该协议。${NC}"
        return 1
    fi

    print_header "${label} 检测（出口 IP：${ip}）"
    echo -e "${CYAN}  脚本版本：${SCRIPT_VERSION}${NC}"
    if [ "$ipflag" == "-6" ]; then
        echo -e "${YELLOW}  提示：部分服务不支持 IPv6，或因 IPv6 路由不通显示「失败(网络连接)」，属正常现象。${NC}"
    fi
    print_separator "IP 基础信息"
    check_ip_info "$ip" "$ipflag"

    echo ""
    print_separator "流媒体 & AI 服务解锁"
    print_line "Netflix"             "$(check_netflix "$ipflag")"
    print_line "Disney+"             "$(check_disney "$ipflag")"
    print_line "YouTube Premium"      "$(check_youtube "$ipflag")"
    print_line "Amazon Prime Video"   "$(check_primevideo "$ipflag")"
    print_line "TikTok"              "$(check_tiktok "$ipflag")"
    print_line "Reddit"              "$(check_reddit "$ipflag")"
    print_line "ChatGPT"             "$(check_chatgpt "$ipflag")"

    print_copy_summary
    return 0
}

# ------------------------------- 交互菜单 ---------------------------------
show_menu() {
    echo -e "${BOLD}${CYAN}"
    echo "========================================"
    echo "        IP 质量体检脚本"
    echo "       版本: ${SCRIPT_VERSION}"
    echo "   (IPv4/IPv6 · 流媒体 · AI 解锁)"
    echo "========================================"
    echo -e "${NC}"
    echo "  1) 检测 IPv4"
    echo "  2) 检测 IPv6"
    echo "  3) 同时检测 IPv4 + IPv6"
    echo "  4) 视频平台测速 (YouTube/X/Telegram/Netflix/TikTok)"
    echo "  0) 退出"
    echo ""
}

main_menu() {
    while true; do
        show_menu
        read -r -p "  请输入选项 [0-4]： " choice
        echo ""
        case "$choice" in
            1) run_tests "-4" ;;
            2) run_tests "-6" ;;
            3) run_tests "-4"; run_tests "-6" ;;
            4) check_platform_speed ;;
            0) echo -e "${GREEN}已退出。${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项，请重新输入。${NC}" ;;
        esac
        echo ""
        read -r -p "  按回车键返回菜单..." _
    done
}

# ------------------------------- 入口 -------------------------------------
check_deps

case "${1:-}" in
    -4) run_tests "-4" ;;
    -6) run_tests "-6" ;;
    "") main_menu ;;
    *)  echo -e "${RED}未知参数：$1${NC}"; echo "用法：bash ipcheck.sh [-4|-6]"; exit 1 ;;
esac
