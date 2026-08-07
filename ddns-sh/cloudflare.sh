domainName=$1
currentIP=$2
send_authArray_Str=$3
IFS='|' read -ra authArray <<< "$send_authArray_Str"
send_subDomain_Str=$4
IFS='|' read -ra SubDomainArray <<< "$send_subDomain_Str"
typeMode=$5
send_EnableCFproxied_Str=$6
IFS='|' read -ra EnableCFproxiedArray <<< "$send_EnableCFproxied_Str"
# echo "cloudflareVar_domainName: $domainName"
# echo "cloudflareVar_currentIP: $currentIP"
# echo "cloudflareVar_authArray: ${#authArray[@]}"
# echo "cloudflareVar_subDomain: ${#SubDomainArray[@]}"
# echo "cloudflareVar_typeMode: $typeMode"
# echo "cloudflareVar_EnableCFproxied: ${#EnableCFproxiedArray[@]}"

# 解析 [Auth] 配置
for dict in "${authArray[@]}"; do
    if [[ $dict == cloudflare_Accunt=* ]]; then
        CF_accunt="${dict#*=}"
    elif [[ $dict == cloudflare_Token=* ]]; then
        CF_token="${dict#*=}"
    elif [[ $dict == cloudflare_zoneID=* ]]; then
        CF_zoneID="${dict#*=}"
    fi
done
# echo "CF_accunt: $CF_accunt"
# echo "CF_token: $CF_token"

# 解构 [EnableCFproxied] 配置项
ExcludedDirectConnectionEntriesArray=()
for i in "${EnableCFproxiedArray[@]}"; do
    if [[ $i == IPv4=* ]]; then
        IPv4ConfProxied="${i#*=}"
    elif [[ $i == IPv6=* ]]; then
        IPv6ConfProxied="${i#*=}"
    else
        ExcludedDirectConnectionEntriesArray+=("$i")
    fi
done

# 统一日志处理：
# - 每次调用 Cloudflare API 都先把响应 JSON 追加到 info.log
# - 如果 success=true：删掉最后一行（不污染日志）
# - 如果 success=false：把最后一行替换成标准错误行（含 Message）
function writeErrMessage() {
    CF_response=$(tail -n 1 info.log | tr -d '\r')
    if echo "$CF_response" | grep -q '"success":true'; then
        sed -i '$d' info.log
        echo "[$(date "+%G/%m/%d %H:%M:%S")] $1 $2 " >> info.log
        return 0
    fi

    x_Message_x=$(echo "$CF_response" | tr -d '\n' | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' | head -n 1)
    [ -z "$x_Message_x" ] && x_Message_x="Unknown error"
    x_Message_x=${x_Message_x//$'\r'/}
    x_Message_x=${x_Message_x//$'\n'/}
    x_Message_x=${x_Message_x//\"/\\\"}
    sed -i '$d' info.log
    echo "[$(date "+%G/%m/%d %H:%M:%S")] $1 $2 \"Message\":\"${x_Message_x}\"" >> info.log
    return 1
}

# Cloudflare API 调用封装：
# - 优先使用 API Token（Authorization: Bearer）
# - 当 cloudflare_Accunt 形如邮箱时，兼容 Global API Key（X-Auth-Email / X-Auth-Key）
cf_api() {
    local method="$1"
    local path="$2"
    local data="$3"
    local url="https://api.cloudflare.com/client/v4${path}"

    local -a auth_headers=()
    if [[ -n "$CF_accunt" && "$CF_accunt" == *"@"* ]]; then
        auth_headers+=(-H "X-Auth-Email: ${CF_accunt}")
        auth_headers+=(-H "X-Auth-Key: ${CF_token}")
    else
        auth_headers+=(-H "Authorization: Bearer ${CF_token}")
    fi

    if [[ "$method" == "GET" || "$method" == "DELETE" ]]; then
        curl -s -X "$method" "$url" "${auth_headers[@]}" -H "Content-Type: application/json"
    else
        curl -s -X "$method" "$url" "${auth_headers[@]}" -H "Content-Type: application/json" --data "$data"
    fi
}

# 通过根域名查询 Zone ID（后续所有 DNS 记录操作都需要 zone_id）
get_zone_id() {
    local resp
    resp=$(cf_api GET "/zones?name=${domainName}&per_page=1")
    local zone_id
    zone_id=$(echo "$resp" | tr -d '\n' | sed -n 's/.*"result":\[{[^}]*"id":"\([a-f0-9]\{32\}\)".*/\1/p')
    if [ -z "$zone_id" ]; then
        echo "$resp" >> info.log
        writeErrMessage "init" "@"
        return 1
    else
        CF_zoneID="$zone_id"
    fi
    return 0
}

# 删除 DNS 记录（按 record_id）
delete_record() {
    cf_api DELETE "/zones/${CF_zoneID}/dns_records/$1"
}

# ttl=1 表示自动 TTL（Cloudflare 语义）
# proxied 按更新参数设置
# 更新 DNS 记录（按 record_id）
update_record() {
    local record_id="$1"
    local proxied="$2"
    if [ "$proxied" != "true" ]; then
        proxied="false"
    fi
    cf_api PUT "/zones/${CF_zoneID}/dns_records/${record_id}" "{\"type\":\"${typeMode}\",\"name\":\"${fullDomain}\",\"content\":\"${currentIP}\",\"ttl\":1,\"proxied\":${proxied}}"
}

# 新增 DNS 记录
add_record() {
    local proxied="$1"
    cf_api POST "/zones/${CF_zoneID}/dns_records" "{\"type\":\"${typeMode}\",\"name\":\"${fullDomain}\",\"content\":\"${currentIP}\",\"ttl\":1,\"proxied\":${proxied}}"
}

# 失败次数累计：任意增/删/改失败，最终退出码为 1，让 main.sh 感知失败
failCount=0

# Token 必填：无论是 API Token 还是 Global API Key，这里都用 cloudflare_Token 传入
if [ -z "$CF_token" ]; then
    echo "[$(date "+%G/%m/%d %H:%M:%S")] init @ \"Message\":\"cloudflare_Token missing\"" >> info.log
    exit 1
fi

# 初始化 Zone ID
if [ -z "$CF_zoneID" ]; then
    get_zone_id
fi

# 拉取当前 Zone 下指定类型（A/AAAA）的所有记录，按页分页
page=1
total_pages=1
CFRecordList=""

while [ "$page" -le "$total_pages" ]; do
    resp=$(cf_api GET "/zones/${CF_zoneID}/dns_records?type=${typeMode}&per_page=100&page=${page}")
    if ! echo "$resp" | grep -q '"success":true'; then
        echo "$resp" >> info.log
        writeErrMessage "query" "@"
        exit 1
    fi

    tp=$(echo "$resp" | tr -d '\n' | sed -n 's/.*"total_pages":\([0-9]\+\).*/\1/p')
    [ -n "$tp" ] && total_pages="$tp"

    while IFS= read -r block; do
        rid=$(echo "$block" | sed -n 's/.*"id":"\([a-f0-9]\{32\}\)".*/\1/p' | head -n 1)
        name=$(echo "$block" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -n 1)
        typ=$(echo "$block" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p' | head -n 1)
        prox=$(echo "$block" | sed -n 's/.*"proxied":\([^,}]*\).*/\1/p' | head -n 1)

        if [ -z "$rid" ] || [ -z "$name" ] || [ "$typ" != "$typeMode" ]; then
            continue
        fi

        if [ "$name" = "$domainName" ]; then
            rr="@"
        else
            case "$name" in
                *".${domainName}") rr="${name%.$domainName}" ;;
                *) continue ;;
            esac
        fi

        [ -n "$CFRecordList" ] && CFRecordList="${CFRecordList}|"
        CFRecordList="${CFRecordList}${rr}=${rid};${prox}"
    done < <(echo "$resp" | tr -d '\n' | sed -e 's/},{"id":/}\n{"id":/g' | grep '{"id":')

    page=$((page + 1))
done

IFS='|' read -ra CFRecordArray <<< "$CFRecordList"
# echo "CFRecordArray: ${#CFRecordArray[@]}"

# 比较 Cloudflare 记录值(子域名)不在配置中的，提交 Cloudflare 进行删除
for CFRecordEntry in "${CFRecordArray[@]}"; do
    found=0
    CF_RR="${CFRecordEntry%%=*}"
    CF_rest="${CFRecordEntry#*=}"
    CF_ID="${CF_rest%%;*}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        if [[ "$CF_RR" == "$SubDomain" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        resp=$(delete_record "${CF_ID}")
        echo "$resp" >> info.log
        if ! writeErrMessage "delete" "${CF_RR}"; then
            failCount=$((failCount + 1))
        fi
    fi
done

# 比较 Cloudflare 记录值(子域名) 与配置中配置的子域名相同时，提交 Cloudflare 进行更新
for CFRecordEntry in "${CFRecordArray[@]}"; do
    CF_RR="${CFRecordEntry%%=*}"
    CF_rest="${CFRecordEntry#*=}"
    CF_ID="${CF_rest%%;*}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        currentIP="${settingEntry#*=}"
        if [[ "$CF_RR" == "$SubDomain" ]]; then
            if [ "${SubDomain}" = "@" ];then
                fullDomain="${domainName}"
            else
                fullDomain="$SubDomain"".""$domainName"
            fi
            # 配置 A/AAAA(直连的指定条目外) 记录值的统一CF 代理
            if [ "${typeMode}" = "A" ]; then
                confProxied="${IPv4ConfProxied#*=}"
            else
                confProxied="${IPv6ConfProxied#*=}"
                # 检查是否在排除列表中
                for i in "${ExcludedDirectConnectionEntriesArray[@]}"; do
                    if [[ "${i%%=*}" == "$CF_RR" ]]; then
                        confProxied="${i#*=}"
                        # echo "CF_RR: $CF_RR, confProxied: $confProxied"
                        break
                    fi
                done
            fi
            resp=$(update_record "${CF_ID}" "${confProxied}")
            echo "$resp" >> info.log
            if ! writeErrMessage "update" "${CF_RR}"; then
                failCount=$((failCount + 1))
            fi
            break  # 找到就跳出内层，避免重复
        fi
    done
done

# 比较 Cloudflare 记录值(子域名)没有在配置中的，提交 Cloudflare 进行添加
for settingEntry in "${SubDomainArray[@]}"; do
    found=0 
    SubDomain="${settingEntry%%=*}"
    currentIP="${settingEntry#*=}"
    for CFRecordEntry in "${CFRecordArray[@]}"; do
        CF_RR="${CFRecordEntry%%=*}"
        if [[ "$CF_RR" == "$SubDomain" ]]; then
            found=1 
            break   
        fi      
    done    
    if [[ $found -eq 0 ]]; then
        if [ "${SubDomain}" = "@" ];then
            fullDomain="${domainName}"
        else
            fullDomain="$SubDomain"".""$domainName"
        fi
        # 配置 A/AAAA(直连的指定条目外) 记录值的统一CF 代理
        if [ "${typeMode}" = "A" ]; then
            confProxied="${IPv4ConfProxied#*=}"
        else
            confProxied="${IPv6ConfProxied#*=}"
            # 检查是否在排除列表中
            for i in "${ExcludedDirectConnectionEntriesArray[@]}"; do
                if [[ "${i%%=*}" == "$SubDomain" ]]; then
                    confProxied="${i#*=}"
                    # echo "SubDomain: $SubDomain, confProxied: $confProxied"
                    break
                fi
            done
        fi
        resp=$(add_record "${confProxied}")
        echo "$resp" >> info.log
        if ! writeErrMessage "add" "${SubDomain}"; then
            failCount=$((failCount + 1))
        fi
    fi
done

if [ "$failCount" -gt 0 ]; then
    exit 1
fi

exit 0
