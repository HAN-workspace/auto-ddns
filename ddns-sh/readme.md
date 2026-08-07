## -------------- ddns-sh 说  明 -------------- 
<font color="red">**重要：本脚本会接管所有子域名 (仅 A/AAAA 主机记录)，没有在配置文件中的将被删除。**</font>
### 运行环境
系统：linux <br>
shell：bash <br>
依赖：curl 及 openssl
 
### 工作目录：
  默认 `~/ddns-sh/` 路径下工作，若自定请修改 main.sh 的第 4 行

### 必需文件：
- **[main.sh](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/main.sh)** 主脚本，判断公网IP是否发生变化的逻辑，读取配置，调用对应的 DNS 服务商API。如：aliyun.sh、cloudflare.sh
- **[aliyun.sh](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/aliyun.sh)** 与*阿里云*交互的 API 脚本，进行主机记录的增删改查操作
- **[cloudflare.sh](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/cloudflare.sh)** 与*cloudflare*交互的 API 脚本，进行主机记录的增删改查操作
- **[domain name](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/example.com.cn)** 配置文件 [参考示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84) 编写属于你的专用配置<br>
此文件名需用你的域名命名 ( *[example.com.cn](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/example.com.cn)* )
- **info.log** 记录：公网IP发生变化、向 *阿里云解析DNS* 交互时的错误信息、添新增子域名的操作也会记录
- **公网IPv4** 初始名字为：`1.1.1.1` 用于比对当前获得的公网IPv4，首次运行本脚本且脚本正常结束时，文件名会被脚本更名为当前公网 IPv4 地址
- **公网IPv6** 初始名字为：`240e-1-1-1` 用于比对当前获得的公网IPv6前缀，首次运行本脚本且脚本正常结束时，文件名会被脚本更名为当前公网 IPv6 前缀

### 语法：
```bash
# 先把 main.sh 添加可执属性 chmod +x main.sh
./main.sh `domain name`
```
例：若你的域名是 *abc.com* 运行程序时以参数形式传入主程序
```bash
./main.sh abc.com
```

### 查看日志：
```bash
cat info.log
```

### 定时任务：
可以借助定时器 crond 设置 */1 每分钟运行一次脚本，实现无人值守
```bash
crontab -e
```
在定时任务中添加 这里表示每 5 分钟运行一次脚本：<br>
`*/5 * * * * /root/ddns-sh/main.sh example.com.cn`

注：只有脚本获得的 “公网IPv4” 或 “公网IPv6” 对比 “公网IPv4/6 文件名” 不同时，脚本才会向下执行。

## domain 内结构：
共五个【section】: [【Auth】](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#auth) [【Direct】](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#direct) [【IPv6】](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#ipv6) [【IPv4】](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#ipv4) [【EnableCFproxied】](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#enablecfproxied)
### 配置示例：abc.com
```txt
[Auth]
# aliyun_ID=abcdefghijk
# aliyun_Secret=lnmopqrstuvwxyx
# 或 （ aliyun / cloudflare 只能使用一个服务商）
cloudflare_Accunt=123456789
cloudflare_Token=09876543210
cloudflare_zoneID=a0b9c8d7e6f5a4b3c2d1e0

[Direct]
reverseProxy=abcd:efff:fe12:3456
nas=a1b2:c3ff:fee4:d5e6
truenas=1234:56ff:fe78:90ab

[IPv6]
@
www
fnos

[IPv4]
@
www
wiki

[EnableCFproxied]
IPv4=true
IPv6=true
nas=false
truenas=true
```
### 说明：
#### 【Auth】<br>
必须配置，作用 DNS 服务商的认证<br>
aliyun_ID= <br>
aliyun_Secret= <br>
或
cloudflare_Accunt= <br>
cloudflare_Token= <br>
**若使用Global API Key，这里都用 cloudflare_Token 传入**<br>
cloudflare_zoneID= <br>
**可选项 填写 zoneID 会更好**<br>

使用以服务商名字方式设计键值对将会调用对应服务商的交互脚本。（ 目前支持 aliyun、cloudflare ）<br>
[返回示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)

#### 【Direct】<br>
在【Direct】内配置可实现直连(仅支持IPv6)，在这里填写 “主机记录=直连主机的IPv6后缀” 即可<br><br>
reverseProxy=“反向代理服务器的IPv6后缀” 本条目是为配置在【IPv6】内的子域名进行反向代理的专项条目<br>
如果某主机不想使用反向代理，删除【IPv6】下的对应条目<br><br>
直连主机填写 "子域名=直连主机IPv6后缀" ( 例：nas.example.com，只需填写 nas=a1b2:c3ff:fee4:d5e6 )<br><br>
配置示例：abc.com<br>
在 DNS 服务商中会生成 <br>

|主机记录|记录类型|记录值|
|--:|:--:|:--|
|nas|AAAA|2???\:x\:x\:x\:a1b2\:c3ff\:fee4\:d5e6|
|truenas|AAAA|2???\:x\:x\:x\:1234\:56ff\:fe78\:90ab|

重要：填写的是主机的后缀、后缀、后缀，**（前缀由脚本自动截取公网IPv6网关，再合并成完整的主机IPv6地址）**<br>
[返回示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)

#### 【IPv6】<br>
这个 section 是为非直连 (即使用反向代理) 的子域名配置使用 <br>
需要在【Direct】填写反向代理 reverseProxy=“反向代理服务器的IPv6后缀” 专项条目（ 例：reverseProxy=abcd\:efff\:fe12\:3456 ）<br><br>
使用反向代理的填写 "子域名"，若没有 "子域名" 请配置一个 '@' ( 例：example.com，只需填写 @ ) <br><br>
配置示例：abc.com<br>
在 DNS 服务商中会生成

|主机记录|记录类型|记录值|
|--:|:--:|:--|
|@|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|
|www|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|
|fnos|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|

注：如果不用 IPv6 (AAAA记录类型) 反向代理，清空【IPv6】这个 section 内的内容<br><br>
重要：使用 【IPv6】的反向代理时 必须在 【Direct】填写反向代理 reverseProxy=“代理服务的IPv6后缀” 条目（ 例：reverseProxy=abcd\:efff\:fe12\:3456 ）<br>
重要：填写的是主机的后缀、后缀、后缀，**（前缀由脚本自动截取公网IPv6网关，再合并成完整的主机IPv6地址）**<br>
[返回示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)

#### 【IPv4】<br>
这个 section 是为非直连 (即反向代理) 的子域名配置使用 <br>
填写 "子域名"，若没有 "子域名" 请配置一个 '@' (例：example.com，只需填写 @ ) <br><br>
配置示例：abc.com<br>
在 DNS 服务商中会生成 <br>

|主机记录|记录类型|记录值|
|--:|:--:|:--|
|@|A|x.x.x.x|
|www|A|x.x.x.x|
|wiki|A|x.x.x.x|

注：如果不用 IPv4 (A记录类型) 请清空 【IPv4】 这个 section 内的内容 <br>
[返回示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)

#### 【EnableCFproxied】<br>
本 section 是 cloudflare 特有的 “开启代理” 模式，其作用是隐藏真实IP 的防护、走CF的 CDN 路由 <br>
`IPv4=`统一配置 即所有A记录类型：true 即CF开启代理，false 即不CF开启代理<br>
`IPv6=`统一配置 即所有AAAA记录类型：true 即CF开启代理，false 即不CF开启代理<br>
       若没有为 【Direct】内的主机记录独立配置的，直连中的所有主机记录默认按*IPv6=*配置项处理CF开启代理<br>
`主机记录=`独立配置 优先级高于*IPv6=*统一配置<br>
          例如：rtsp=false 则不管*IPv6=*配置项是否为true，都为不CF开启代理<br><br>
配置示例：abc.com<br>
在 cloudflare DNS 中会生成

|名称|类型|内容|代理状态|
|--:|:--:|:--|:--|
|abc.com|A|x.x.x.x|已代理|
|abc.com|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|已代理|
|www.abc.com|A|x.x.x.x|已代理|
|www.abc.com|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|已代理|
|wiki.abc.com|A|x.x.x.x|已代理|
|fnos.abc.com|AAAA|2???\:x\:x\:x\:abcd\:efff\:fe12\:3456|已代理|
|nas.abc.com|AAAA|2???\:x\:x\:x\:a1b2\:c3ff\:fee4\:d5e6|仅DNS|
|truenas.abc.com|AAAA|2???\:x\:x\:x\:1234\:56ff\:fe78\:90ab|仅DNS|