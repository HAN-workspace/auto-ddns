domainName=$1
currentIP=$2
send_authArray_Str=$3
IFS='|' read -ra camArray <<< "$send_authArray_Str"
send_subDomain_Str=$4
IFS='|' read -ra SubDomainArray <<< "$send_subDomain_Str"
typeMode=$5
# echo "tencentVar_domainName: $domainName"
# echo "tencentVar_currentIP: $currentIP"
# echo "tencentVar_camArray: ${#camArray[@]}"
# echo "tencentVar_subDomain: ${#SubDomainArray[@]}"
# echo "tencentVar_typeMode: $typeMode"

# 解析 [Auth] 配置
for dict in "${camArray[@]}"; do
    if [[ $dict == tencent_ID=* ]]; then
        Tencent_ID="${dict#*=}"
    elif [[ $dict == tencent_KEY=* ]]; then
        Tencent_KEY="${dict#*=}"
    fi
done
# ========== 输出结果验证 ==========
# echo "SubDomainArray (共 ${#SubDomainArray[@]} 项):"
# for item in "${SubDomainArray[@]}"; do
#     echo "$item"
# done


# 处理交互信息 (提取 腾讯云DNS 响应的 Error/Message 并写入 info.log)
# 成功判定：响应中不包含 '"Error":{' 即视为成功；失败时会返回 "Error":{"Code":"...","Message":"..."}
function writeErrMessage() {
    # 取 info.log 最末一行（刚写入的 API 响应 JSON），并去掉 Windows 回车符
    tencent_response=$(tail -n 1 info.log | tr -d '\r')

    # ========== 成功分支 ==========
    # 若响应中不包含 "Error":{ 即视为成功；直接删除末尾的原始响应行，不追加额外信息
    if ! echo "$tencent_response" | grep -q '"Error":{'; then
        sed -i '$d' info.log
        echo "[$(date "+%G/%m/%d %H:%M:%S")] $1 $2 " >> info.log
        return 0
    fi

    # ========== 失败分支 ==========
    # 尝试提取 Message（若存在则取第一条 Message 内容，不存在则兜底）
    x_Message_x=$(echo "$tencent_response" | tr -d '\n' | sed -n 's/.*"Message":"\([^"]*\)".*/\1/p' | head -n 1)
    [ -z "$x_Message_x" ] && x_Message_x="Unknown error"
    # 去掉残留换行/回车，以及对双引号做转义，避免破坏日志行格式
    x_Message_x=${x_Message_x//$'\r'/}
    x_Message_x=${x_Message_x//$'\n'/}
    x_Message_x=${x_Message_x//\"/\\\"}

    # 删除末尾原始响应行，替换为统一格式的错误行
    sed -i '$d' info.log
    echo "[$(date "+%G/%m/%d %H:%M:%S")] $1 $2 \"Message\":\"${x_Message_x}\"" >> info.log
    return 1
}

# ========== 腾讯云 TC3-HMAC-SHA256 签名请求函数 ==========
send_request() {
    local action="$1"
    local payload="$2"
    local service="dnspod"
    local host="dnspod.tencentcloudapi.com"
    local region=""
    local version="2021-03-23"
    local algorithm="TC3-HMAC-SHA256"
    local timestamp=$(date +%s)
    local date=$(date -u -d @$timestamp +"%Y-%m-%d")

    # ************* 步骤 1：拼接规范请求串 *************
    local http_request_method="POST"
    local canonical_uri="/"
    local canonical_querystring=""
    local canonical_headers="content-type:application/json; charset=utf-8\nhost:$host\nx-tc-action:$(echo $action | awk '{print tolower($0)}')\n"
    local signed_headers="content-type;host;x-tc-action"
    local hashed_request_payload=$(printf '%s' "$payload" | openssl sha256 -hex | awk '{print $2}')
    local canonical_request="$http_request_method\n$canonical_uri\n$canonical_querystring\n$canonical_headers\n$signed_headers\n$hashed_request_payload"

    # ************* 步骤 2：拼接待签名字符串 *************
    local credential_scope="$date/$service/tc3_request"
    local hashed_canonical_request=$(printf '%b' "$canonical_request" | openssl sha256 -hex | awk '{print $2}')
    local string_to_sign="$algorithm\n$timestamp\n$credential_scope\n$hashed_canonical_request"

    # ************* 步骤 3：计算签名 *************
    local secret_date=$(printf '%s' "$date" | openssl dgst -sha256 -mac hmac -macopt key:"TC3$Tencent_KEY" | awk '{print $2}')
    local secret_service=$(printf '%s' "$service" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_date" | awk '{print $2}')
    local secret_signing=$(printf '%s' "tc3_request" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_service" | awk '{print $2}')
    local signature=$(printf '%b' "$string_to_sign" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_signing" | awk '{print $2}')

    # ************* 步骤 4：拼接 Authorization *************
    local authorization="$algorithm Credential=$Tencent_ID/$credential_scope, SignedHeaders=$signed_headers, Signature=$signature"

    # ************* 步骤 5：构造并发起请求 *************
    curl -s -XPOST "https://$host" \
        -d "$payload" \
        -H "Authorization: $authorization" \
        -H "Content-Type: application/json; charset=utf-8" \
        -H "Host: $host" \
        -H "X-TC-Action: $action" \
        -H "X-TC-Timestamp: $timestamp" \
        -H "X-TC-Version: $version" \
        -H "X-TC-Region: $region"
}

# ========== DNS 操作函数（使用腾讯云 DNSPod API v3） ==========

# 删除腾讯云DNS记录
# API: DeleteRecord，参数: Domain, RecordId
delete_record() {
    local recordId="$1"
    local payload="{\"Domain\":\"${domainName}\",\"RecordId\":${recordId}}"
    send_request "DeleteRecord" "$payload"
}

# 添加记录值
# API: CreateRecord，参数: Domain, SubDomain, RecordType, RecordLine, Value, TTL
# 注意：腾讯云 SubDomain 对于根域名使用 "@"，RecordLine 必填，这里用 "默认"
create_record() {
    local payload="{\"Domain\":\"${domainName}\",\"SubDomain\":\"${SubDomain}\",\"RecordType\":\"${typeMode}\",\"RecordLine\":\"默认\",\"Value\":\"${currentIP}\",\"TTL\":600}"
    send_request "CreateRecord" "$payload"
}

# 更新记录值
# API: ModifyRecord，参数: Domain, SubDomain, RecordId, RecordType, RecordLine, Value, TTL
modify_record() {
    local recordId="$1"
    local payload="{\"Domain\":\"${domainName}\",\"SubDomain\":\"${SubDomain}\",\"RecordId\":${recordId},\"RecordType\":\"${typeMode}\",\"RecordLine\":\"默认\",\"Value\":\"${currentIP}\",\"TTL\":600}"
    send_request "ModifyRecord" "$payload"
}

# 请求记录值 (获取当前域名下所有 DNS 记录)
# API: DescribeRecordList，参数: Domain, Limit
query_records() {
    local payload="{\"Domain\":\"${domainName}\",\"Limit\":3000}"
    send_request "DescribeRecordList" "$payload"
}


# ========== 分析腾讯云 DNS 记录 ==========
tencentRecords=$(query_records)
# echo "tencentRecords: $tencentRecords"

# 提取 RecordList 数组内容，拆分为单条记录块
# 腾讯云返回结构: { "Response": { "RecordList": [ { "RecordId":123, "Name":"www", "Type":"A", ... }, ... ] } }
recordListRaw=$(echo "$tencentRecords" | tr -d '\n' | sed -n 's/.*"RecordList":\[\(.*\)\].*/\1/p')

if [ "$typeMode" = "AAAA" ]; then
# 提取 IPv6 记录 (Type=AAAA)
    tencentIPv6Record=""
    while IFS= read -r block; do
        if [ -n "$block" ]; then
            # 提取 Name (即 RR / 子域名前缀，根域名为 @)
            Name=$(echo "$block" | sed -n 's/.*"Name":"\([^"]*\)".*/\1/p')
            # 提取 RecordId (数字，不带引号)
            RecordId=$(echo "$block" | sed -n 's/.*"RecordId":\([0-9]*\).*/\1/p')
            # 提取 Type
            typ=$(echo "$block" | sed -n 's/.*"Type":"\([^"]*\)".*/\1/p')

            if [ "$typ" = "AAAA" ] && [ -n "$Name" ] && [ -n "$RecordId" ]; then
                [ -n "$tencentIPv6Record" ] && tencentIPv6Record="${tencentIPv6Record}|"
                tencentIPv6Record="${tencentIPv6Record}${Name}=${RecordId}"
            fi
        fi
    done < <(echo "$recordListRaw" | sed -e 's/},{/}\n{/g' | grep '{')
    IFS='|' read -ra tencentRecordArray <<< "$tencentIPv6Record"
else
# 提取 IPv4 记录 (Type=A)
    tencentIPv4Record=""
    while IFS= read -r block; do
        if [ -n "$block" ]; then
            # 提取 Name
            Name=$(echo "$block" | sed -n 's/.*"Name":"\([^"]*\)".*/\1/p')
            # 提取 RecordId
            RecordId=$(echo "$block" | sed -n 's/.*"RecordId":\([0-9]*\).*/\1/p')
            # 提取 Type
            typ=$(echo "$block" | sed -n 's/.*"Type":"\([^"]*\)".*/\1/p')

            if [ "$typ" = "A" ] && [ -n "$Name" ] && [ -n "$RecordId" ]; then
                [ -n "$tencentIPv4Record" ] && tencentIPv4Record="${tencentIPv4Record}|"
                tencentIPv4Record="${tencentIPv4Record}${Name}=${RecordId}"
            fi
        fi
    done < <(echo "$recordListRaw" | sed -e 's/},{/}\n{/g' | grep '{')
    IFS='|' read -ra tencentRecordArray <<< "$tencentIPv4Record"
fi

# 比较 腾讯云DNS 记录值(子域名)不在配置中的，提交 腾讯云DNS 进行删除
for tencentRecordEntry in "${tencentRecordArray[@]}"; do
    found=0
    tencent_Name="${tencentRecordEntry%%=*}"
    tencent_RecordId="${tencentRecordEntry#*=}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        if [[ "$tencent_Name" == "$SubDomain" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        # 删除记录
        delete_record "${tencent_RecordId}" 1>> info.log
        writeErrMessage "delete" "${tencent_Name}"
    fi
done


# 比较 腾讯云DNS 记录值(子域名) 与配置中配置的子域名相同时，提交 腾讯云DNS 进行更新
for tencentRecordEntry in "${tencentRecordArray[@]}"; do
    tencent_Name="${tencentRecordEntry%%=*}"
    tencent_RecordId="${tencentRecordEntry#*=}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        currentIP="${settingEntry#*=}"
        if [[ "$tencent_Name" == "$SubDomain" ]]; then
            # 更新记录
            if [ "${SubDomain}" = "@" ];then
                fullDomain="${domainName}"
            else
                fullDomain="$SubDomain"".""$domainName"
            fi
            modify_record "${tencent_RecordId}" 1>> info.log
            writeErrMessage "update" "${tencent_Name}"
            break  # 找到就跳出内层，避免重复
        fi
    done
done

# 比较 腾讯云DNS 记录值(子域名)没有在配置中的，提交 腾讯云DNS 进行添加
for settingEntry in "${SubDomainArray[@]}"; do
    found=0
    SubDomain="${settingEntry%%=*}"
    currentIP="${settingEntry#*=}"
    for tencentRecordEntry in "${tencentRecordArray[@]}"; do
        tencent_Name="${tencentRecordEntry%%=*}"
        if [[ "$tencent_Name" == "$SubDomain" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        # 新增记录
        create_record 1>> info.log
        writeErrMessage "add" "${SubDomain}"
    fi
done
