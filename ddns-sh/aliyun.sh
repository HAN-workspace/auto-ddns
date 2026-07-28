domainName=$1
currentIP=$2
send_ramArray_Str=$3
IFS='|' read -ra ramArray <<< "$send_ramArray_Str"
send_subDomain_Str=$4
IFS='|' read -ra SubDomainArray <<< "$send_subDomain_Str"
typeMode=$5

# 验证变量传入
# echo "aliyunFile_domainName: $domainName"
# echo "aliyunFile_currentIP: $currentIP"
# echo "aliyunFile_ramArray: ${#ramArray[@]}"
# echo "aliyunFile_subDomain: ${#SubDomainArray[@]}"
# echo "aliyunFile_typeMode: $typeMode"

# 解析 RAM 配置文件
for dict in "${ramArray[@]}"; do
    if [[ $dict == aliyun_ID=* ]]; then
        Ali_Key="${dict#*=}"
    elif [[ $dict == aliyun_SE=* ]]; then
        Ali_Secret="${dict#*=}"
    fi
done
# ========== 输出结果验证 ==========
# echo "SubDomainArray (共 ${#SubDomainArray[@]} 项):"
# for item in "${SubDomainArray[@]}"; do
#     echo "$item"
# done


# 处理交互信息 (提取 阿里云解释DNS 响应的 "Message":"........")
function writeErrMessage() {
    # 提取错误信息
    ali_response=$(tail -n 1 info.log)
    # 探头去尾，只保留 Message
    x_Message=${ali_response#*Message\"\:\"}
    if [ "${x_Message%%025/*}" == "2" ];then
        `sed -i '$d' info.log`
    else
        # 记录 更新失败 信息
        x_Message_x=${x_Message%\",\"*}
        `sed -i '$d' info.log`
        echo "[$(date "+%G/%m/%d %H:%M:%S")] $1 $2 \"Message\":\"${x_Message_x}\"" >> info.log
    fi
}

# 加密函数
function urlencode() {
    # urlencode <string>
    out=""
    while read -n1 c
    do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out`printf '%%%02X' "'$c"`" ;;
        esac
    done
    echo -n $out
}
# URL加密命令
function enc() {
    echo -n "$1" | urlencode
}

# 发送请求函数
send_request() {
    # 将所有参数放入数组（key=encoded_value）
    local params=()
    
    # 处理基本参数
    params+=("AccessKeyId=$(enc "${Ali_Key}")")
    params+=("Action=$(enc "$1")")
    params+=("Format=$(enc "json")")
    params+=("Version=$(enc "2015-01-09")")
    
    # 解析第二个参数，将其拆分为单独的参数并对值进行编码
    IFS='&' read -ra extra_params <<< "$2"
    for param in "${extra_params[@]}"; do
        if [ -n "$param" ]; then
            local key="${param%%=*}"
            local value="${param#*=}"
            # 注意：有些值已经被编码过了，需要先解码再编码
            # 这里我们假设传入的值未被编码，直接编码
            params+=("${key}=$(enc "${value}")")
        fi
    done
    
    # 按字典序排序参数（只按 key 排序）
    IFS=$'\n' sorted_params=($(sort <<<"${params[*]}"))
    unset IFS
    
    # 构建有序的参数字符串
    local args=""
    local first=true
    for param in "${sorted_params[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            args="$args&"
        fi
        args="$args$param"
    done
    
    # 计算签名
    local string_to_sign="GET&%2F&$(enc "${args}")"
    local hash=$(echo -n "$string_to_sign" | openssl dgst -sha1 -hmac "${Ali_Secret}&" -binary | openssl base64)
    
    # 发送请求
    curl -s "http://alidns.aliyuncs.com/?${args}&Signature=$(enc "${hash}")"
}

# 添加记录值 (RecordID)
add_record() {
    send_request "AddDomainRecord" "DomainName=${domainName}&RR=${SubDomain}&SignatureMethod=HMAC-SHA1&SignatureNonce=${signaturenonce}&SignatureVersion=1.0&TTL=600&Timestamp=${timestamp}&Type=${typeMode}&Value=${currentIP}"
}

# 删除阿里云DNS记录
delete_record() {
    send_request "DeleteDomainRecord" "RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=${signaturenonce}&SignatureVersion=1.0&TTL=600&Timestamp=${timestamp}"
}

# 更新记录值 (RecordID)
update_record() {
    send_request "UpdateDomainRecord" "RR=${SubDomain}&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=${signaturenonce}&SignatureVersion=1.0&TTL=600&Timestamp=${timestamp}&Type=${typeMode}&Value=${currentIP}"
}

# 请求记录值 (RecordID)
query_recordid() {
    send_request "DescribeSubDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=${signaturenonce}&SignatureVersion=1.0&SubDomain=${fullDomain}&Timestamp=${timestamp}"
}
query_records() {
    send_request "DescribeDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=${signaturenonce}&SignatureVersion=1.0&DomainName=${domainName}&Timestamp=${timestamp}&PageNumber=1&PageSize=100"
}


# 分析阿里云DNS记录
signaturenonce="${RANDOM}$(date +%s%N)"
timestamp=`date -u "+%Y-%m-%dT%H:%M:%SZ"`
aliRecords=`query_records`
# echo "aliRecords: $aliRecords"

if [ "$typeMode" = "AAAA" ]; then
# 提取 IPv6 记录 (Type=AAAA)
    aliIPv6Record=""
    # 使用 sed 提取每个记录块
    while IFS= read -r block; do
        if [ -n "$block" ]; then
            # 提取 RR
            rr=$(echo "$block" | sed -n 's/.*"RR":"\([^"]*\)".*/\1/p')
            # 提取 RecordId
            rid=$(echo "$block" | sed -n 's/.*"RecordId":"\([^"]*\)".*/\1/p')
            # 提取 Type
            typ=$(echo "$block" | sed -n 's/.*"Type":"\([^"]*\)".*/\1/p')
            
            if [ "$typ" = "AAAA" ] && [ -n "$rr" ] && [ -n "$rid" ]; then
                [ -n "$aliIPv6Record" ] && aliIPv6Record="${aliIPv6Record}|"
                aliIPv6Record="${aliIPv6Record}${rr}=${rid}"
            fi
        fi
    done < <(echo "$aliRecords" | sed -e 's/},{/}\n{/g' -e 's/\[//' -e 's/\]//' -e 's/^{//' -e 's/}$//' | grep '{')
    IFS='|' read -ra aliRecordArray <<< "$aliIPv6Record"
else
# 提取 IPv4 记录 (Type=A)
    aliIPv4Record=""
    # 使用 sed 提取每个记录块
    while IFS= read -r block; do
        if [ -n "$block" ]; then
            # 提取 RR
            rr=$(echo "$block" | sed -n 's/.*"RR":"\([^"]*\)".*/\1/p')
            # 提取 RecordId
            rid=$(echo "$block" | sed -n 's/.*"RecordId":"\([^"]*\)".*/\1/p')
            # 提取 Type
            typ=$(echo "$block" | sed -n 's/.*"Type":"\([^"]*\)".*/\1/p')
            
            if [ "$typ" = "A" ] && [ -n "$rr" ] && [ -n "$rid" ]; then
                [ -n "$aliIPv4Record" ] && aliIPv4Record="${aliIPv4Record}|"
                aliIPv4Record="${aliIPv4Record}${rr}=${rid}"
            fi
        fi
    done < <(echo "$aliRecords" | sed -e 's/},{/}\n{/g' -e 's/\[//' -e 's/\]//' -e 's/^{//' -e 's/}$//' | grep '{')
    IFS='|' read -ra aliRecordArray <<< "$aliIPv4Record"
fi

# 比较 阿里云DNS 记录值(子域名)不在配置中的，提交 阿里云DNS 进行删除
# delRecords=()
for aliRecordEntry in "${aliRecordArray[@]}"; do
    found=0
    ali_RR="${aliRecordEntry%%=*}"
    ali_ID="${aliRecordEntry#*=}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        if [[ "$ali_RR" == "$SubDomain" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        # delRecords+=("$ali_ID")
        # 删除记录
        signaturenonce="${RANDOM}$(date +%s%N)"
        timestamp=`date -u "+%Y-%m-%dT%H:%M:%SZ"`
        delete_record ${ali_ID} 1>> info.log
        writeErrMessage "delete" "${ali_RR}"
        # 避免 API 调用过快，休息 1 秒
        # sleep $(RANDOM %3)            
    fi
done
# echo "差集: ${delRecords[@]}"


# 比较 阿里云DNS 记录值(子域名) 与配置中配置的子域名相同时，提交 阿里云DNS 进行更新
# updateRecords=()
for aliRecordEntry in "${aliRecordArray[@]}"; do
    ali_RR="${aliRecordEntry%%=*}"
    ali_ID="${aliRecordEntry#*=}"
    for settingEntry in "${SubDomainArray[@]}"; do
        SubDomain="${settingEntry%%=*}"
        currentIP="${settingEntry#*=}"
        if [[ "$ali_RR" == "$SubDomain" ]]; then
            # updateRecords+=("$ali_RR""=""$ali_ID")
            # 更新记录
            if [ "${SubDomain}" = "@" ];then
                fullDomain="${domainName}"
            else
                fullDomain="$SubDomain"".""$domainName"
            fi
            signaturenonce="${RANDOM}$(date +%s%N)"
            timestamp=`date -u "+%Y-%m-%dT%H:%M:%SZ"`
            update_record ${ali_ID} 1>> info.log
            writeErrMessage "update" "${SubDomain}"
            # 避免 API 调用过快，休息 1 秒
            # sleep $(RANDOM %3)            
            break  # 找到就跳出内层，避免重复
        fi
    done
done
# echo "交集: ${updateRecords[@]}"

# 比较 阿里云DNS 记录值(子域名)没有在配置中的，提交 阿里云DNS 进行添加
# addRecords=()
for settingEntry in "${SubDomainArray[@]}"; do
    found=0 
    SubDomain="${settingEntry%%=*}"
    currentIP="${settingEntry#*=}"
    for aliRecordEntry in "${aliRecordArray[@]}"; do
        ali_RR="${aliRecordEntry%%=*}"
        if [[ "$ali_RR" == "$SubDomain" ]]; then
            found=1 
            break   
        fi      
    done    
    if [[ $found -eq 0 ]]; then
        # addRecords+=("$SubDomain""=""$currentIP")
        # 新增记录
        signaturenonce="${RANDOM}$(date +%s%N)" 
        timestamp=`date -u "+%Y-%m-%dT%H:%M:%SZ"`
        add_record 1>> info.log
        writeErrMessage "add" "${SubDomain}"
        # 避免 API 调用过快，休息 1 秒
        # sleep $(RANDOM %3)
    fi
done
# echo "差集: ${addRecords[@]}"

# 检查 阿里的 DNS 生效没有
# DNS-IPv4-Records="`nslookup -query=A ${domain} 223.6.6.6 |grep "Address"|grep -v ":53" |awk '{print $2}'`"
# DNS-IPv6-Records="`nslookup -query=AAAA $(domain) 223.5.5.5 | grep "Address" | grep -v ":53" | awk '{print $2}'`"