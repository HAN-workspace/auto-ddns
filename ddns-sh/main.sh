#!/bin/bash

# 进入工作目录
cd ~/ddns-sh/

# 限制 info.log 文件记录总数，保留最多 50 条
function logTotalEntries(){
    while [ `grep -c ".*" info.log` -gt 50 ];do
        sed -i '1d' info.log
    done
}

# ========== 参数校验 ==========
# 没有参数传入 $1 为空，此时判断为假，执行 fileErr 函数，结束脚本。
if [ -z $1 ];then logTotalEntries;echo -n "[$(date "+%G/%m/%d %H:%M:%S")] 执行方式错误(需跟配置文件)" >> info.log;exit 1;fi
# -f 判断有没有这个文，没有就执行 fileErr 函数，结束脚本。
if [ ! -f $1 ];then logTotalEntries;echo -n "[$(date "+%G/%m/%d %H:%M:%S")] 文件 $1 不存在" >> info.log;exit 1;fi  
# -s 判断文件是否为空，空则执行 fileErr 函数，结束脚本。
if [ ! -s $1 ];then logTotalEntries;echo -n "[$(date "+%G/%m/%d %H:%M:%S")] $1 空文件" >> info.log;exit 1;fi

# 下面代码不再使用 $1 变量，改用直观的 domain 变量
domainName="$1"
# 预配解构配置文件开关变量
Has_the_configuration_file_been_deconstructed=false

# ##### ***** ===== ----- 配置文件解析 方法 开始 ----- ===== ***** #####
function getConfigurationItems(){
    # 定向输入域名文件中内容，循环读得每行的内容
    configArray=()    # 声明为数组

    while IFS= read -r line; do
        # 一行判断：跳过空行、#开头、空格/tab开头的行
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]+ ]] && continue
        configArray+=("$line")    # 数组追加元素
    done < "${domainName}"
    # ========== 输出结果验证 ==========
    # echo "configArray (共 ${#configArray[@]} 项):"
    # for item in "${configArray[@]}"; do
    #     echo "$item"
    # done

    # 辅助函数：查找 section 的索引
    find_section_index() {
        local section="$1"
        local i=0
        for item in "${configArray[@]}"; do
            local trimmed_item=$(echo "$item" | tr -d '[:space:]')
            local trimmed_section=$(echo "$section" | tr -d '[:space:]')
            if [ "$trimmed_item" = "$trimmed_section" ]; then
                echo "$i"
                return 0
            fi
            ((i++))
        done
        echo "-1"
        return 1
    }

    # 获取各个 section 的索引
    ramIndex=$(find_section_index "[RAM]")
    directIndex=$(find_section_index "[Direct]")
    ipv6Index=$(find_section_index "[IPv6]")
    ipv4Index=$(find_section_index "[IPv4]")
    
    # ========== 输出结果验证 ==========
    # echo "RAMindex: $ramIndex, ipv4Index: $ipv4Index, ipv6Index: $ipv6Index, directIndex: $directIndex"

    # 拆分配置文件内容到不同的数组中
    ramArray=()    # 声明为数组
    directArray=()    # 声明为数组
    ipv6Array=()    # 声明为数组
    ipv4Array=()    # 声明为数组
    reverseProxyArrayIP=""

    # 确定各个 section 的顺序和边界
    # 将所有索引放入数组并排序
    sections=()
    [[ $ramIndex != "-1" ]] && sections+=("$ramIndex:RAM")
    [[ $directIndex != "-1" ]] && sections+=("$directIndex:Direct")
    [[ $ipv6Index != "-1" ]] && sections+=("$ipv6Index:IPv6")
    [[ $ipv4Index != "-1" ]] && sections+=("$ipv4Index:IPv4")
    
    # 按索引排序
    IFS=$'\n' sorted_sections=($(sort <<<"${sections[*]}"))
    unset IFS
    
    # 创建有序的 section 列表
    section_order=()
    for sec in "${sorted_sections[@]}"; do
        section_order+=("${sec#*:}")
    done
    
    # 处理各个 section 的内容
    current_section=""
    for ((i=0; i<${#configArray[@]}; i++)); do
        item="${configArray[i]}"
        
        # 检查是否是新的 section
        if [[ "$item" == "[RAM]" ]]; then
            current_section="RAM"
            continue
        elif [[ "$item" == "[Direct]" ]]; then
            current_section="Direct"
            continue
        elif [[ "$item" == "[IPv6]" ]]; then
            current_section="IPv6"
            continue
        elif [[ "$item" == "[IPv4]" ]]; then
            current_section="IPv4"
            continue
        fi
        
        # 根据当前 section 处理内容
        case "$current_section" in
            RAM)
                ramArray+=("$item")
                ;;
            Direct)
                key="${item%%=*}"
                value="${item#*=}"
                if [ "$key" == "reverseProxy" ]; then
                    reverseProxyArrayIP="${prefix}:${value}"
                else
                    ipv6Array+=("${key}=${prefix}:${value}")
                fi
                ;;
            IPv6)
                if [ -n "$reverseProxyArrayIP" ]; then
                    ipv6Array+=("${item}=${reverseProxyArrayIP}")
                fi
                ;;
            IPv4)
                ipv4Array+=("${item}=${currentIPv4}")
                ;;
        esac
    done
    
    # ========== 输出结果验证 ==========
    # echo "ramArray (共 ${#ramArray[@]} 项):"
    # for item in "${ramArray[@]}"; do
    #     echo "$item"
    # done
    # echo "ipv6Array (共 ${#ipv6Array[@]} 项):"
    # for item in "${ipv6Array[@]}"; do
    #     echo "$item"
    # done
    # echo "ipv4Array (共 ${#ipv4Array[@]} 项):"
    # for item in "${ipv4Array[@]}"; do
    #     echo "$item"
    # done
}
# ##### ***** ===== ----- 配置文件解析 方法 结束 ----- ===== ***** #####

# 获得公网 IPv4 地址
gateway_ip4=$(ip route | awk '/^default/ {print $3; exit}')
if [[ $gateway_ip4 =~ ^10.*|192.168.*|127.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|100.64.* ]];then
    if [[ $gateway_ip4 =~ ^100.64.* ]];then
        logTotalEntries
        echo -n "[$(date "+%G/%m/%d %H:%M:%S")]  ${gateway_ip4} 线路没有公网 IPv4 地址" >> info.log
        currentIPv4="None"
    else
        currentIPv4=$(wget -qO- -t1 -T2 http://ip.3322.net)
        logTotalEntries
    fi
else
    currentIPv4=$(ip addr show pppoe-wan | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    # echo "main.sh_gateway_ip4_currentIPv4=$currentIPv4"
fi

# 提取本机有效公网 IPv6 地址前缀， 排除 fd::/8 (ULA) 和 fe80::/10 (链路本地)
ipv6_addr=$(ip -6 addr show | grep -v deprecated | grep -w "scope global" | grep -v "^[[:space:]]*inet6 fd" | grep -v "^ [[:space:]]*inet6 fe80" | awk '{print $2}' | head -1)

# 检查是否有有效的公网 IPv6 地址
if [ ! -z "$ipv6_addr" ]; then
    # 提取前缀（取 /64 前缀，即前 4 段）
    prefix=$(echo "$ipv6_addr" | cut -d':' -f1-4)
    # 检查是否成功提取前缀
    if [ ! -z "$prefix" ]; then
        # 读取上次的公网 IPv6 地址(以文件方式保存，文件名就是 IP 地址)
        lastIPv6=`ls | grep -E "^([0-9a-f]{1,4}-){3}[0-9a-f]{1,4}$"`
        # 将冒号替换为横线
        currentIPv6=$(echo "$prefix" | tr ':' '-')
        # echo "currentIPv6：$currentIPv6 -- lastIPv6：$lastIPv6"
        if [ ! "${lastIPv6}" = "${currentIPv6}" ]; then 
            getConfigurationItems
            Has_the_configuration_file_been_deconstructed=true
            # echo "ipv6Array: ${ipv6Array[@]}"
            if [ ! -z "${ipv6Array[0]}" ]; then
                send_ramArray_Str=$(IFS='|'; echo "${ramArray[*]}")
                send_subDomain_Str=$(IFS='|'; echo "${ipv6Array[*]}")
                send_directArray_Str=$(IFS='|'; echo "${directArray[*]}")
                # echo "IPv6 go Aiyun"
                bash ./aliyun.sh $domainName $currentIPv6 ${send_ramArray_Str} ${send_subDomain_Str} "AAAA"
                if [ $? -eq 0 ];        then
                    echo "[$(date "+%G/%m/%d %H:%M:%S")]  ${lastIPv6}"' --> '"${currentIPv6}" >> info.log
                    mv $lastIPv6 $currentIPv6
                fi
            fi
        fi
    fi  
fi

# 读取上次的公网 IPv4 地址(以文件方式保存，文件名就是 IP 地址)
lastIPv4=`ls | grep "[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}"`
# echo "currentIPv4：$currentIPv4 -- lastIPv4：$lastIPv4"
if [ ! "${lastIPv4}" = "${currentIPv4}" ]; then 
    if [ $Has_the_configuration_file_been_deconstructed==false ]; then
        getConfigurationItems
    fi
    # echo "ipv4Array: ${ipv4Array[@]}"
    if [ ! -z "${ipv4Array[0]}" ]; then
        send_ramArray_Str=$(IFS='|'; echo "${ramArray[*]}")
        send_subDomain_Str=$(IFS='|'; echo "${ipv4Array[*]}")
        # echo "IPv4 go Aiyun"
        bash ./aliyun.sh $domainName $currentIPv4 ${send_ramArray_Str} ${send_subDomain_Str} "A"
        if [ $? -eq 0 ];        then
            echo "[$(date "+%G/%m/%d %H:%M:%S")]  ${lastIPv4}"' --> '"${currentIPv4}" >> info.log
            mv $lastIPv4 $currentIPv4
        fi
    fi
fi
