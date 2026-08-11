[立即下载 latest 版：ddns-sh.tar](https://gitee.com/HAN-workspace/auto-ddns/releases/download/latest/ddns-sh.tar)<br>
## 介绍
auto-ddns 是轻量级的动态dns，实现自动调用 API 同步公网 IP 到域名托管商 ( 支持：阿里云 、 cloudflare )<br>
支持 IPv4/6 动态公网地址，主机记录(A/AAAA)的增删改查。<br>
<font color="red">**重要：本脚本会对 A/AAAA 类型的记录进行更新、新增、删除操作，对没有在配置文件中的记录将被删除(仅 A/AAAA 主机记录)。**</font>

## 软件架构
纯 linux bash 脚本，可运行于精简过的 bash 下，如 OpenWrt<br>
依赖：curl 及 openssl <br>
测试环境：debian 13 、 OpenWrt 25.12.5<br>

## 目录结构
<pre>auto-ddns/
    ├── readme.md （github 专属简介）
    ├── readme.osc.md （gitee 专属简介）
    ├── license.md （MIT License）
    ├── ddns-sh/
    │     *  ├── 1.1.1.1       （初始 IPv4 地址命名的文件）
    │     *  ├── 240e-1-1-1    （初始 IPv6 地址命名的文件）
    │     *  ├── example.com.cn（配置文件--请以域名名字命名）
    │     *  ├── main.sh       （主程序）
    │   or*  ├── aliyun.sh     （阿里云 DNS API）
    │   or*  ├── cloudflare.sh （Cloudflare DNS API）
    │        ├── tencent.sh    （待办任务：腾讯云 DNS API）
    │     *  ├── info.log      （记录执行信息）
    │        ├── changelog.md  （版本变更日志）
    │        ├── readme.md     （github 专属详细说明）
    │        └── readme.osc.md （gitee 专属详细说明）
    ├── ddns-py/ （待办任务）
    │        └── ... 
    └── ddns-go/ （待办任务）
             └── ... 
</pre>

## 安装教程
绿色脚本 无需安装 解压即用<br>
只需 [ddns-sh](https://gitee.com/HAN-workspace/auto-ddns/tree/main/ddns-sh) 目录中的文件<br>
标记为 `*` 为必要文件，or* 为可选的必要文件（选择用于你的域名托管商 API 即可）<br>

 ## 使用说明
请阅读 [详细说明](https://gitee.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.osc.md) 文件。
- 编写的属于你的[配置文件](https://gitee.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/example.com.cn) （该配置文件以你的域名名字命名）[查看配置文件示例](https://gitee.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.osc.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)
- 使主程序可运行  `chmod +x main.sh`
- 直接运行  `./main.sh “配置文件名”`
- 添加到任务让程序定时运行 `crontab -e` (可选)<br>
  粘贴 `*/5 * * * * /ddns-sh的绝对路径/main.sh 配置文件名`

## 技巧使用
- 多域名<br>
  编写多个配置文件，每个配置文件以域名名字命名，如 `example.com.cn`、`example.net`、... 等
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh example.com.cn`
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh example.net`
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh xxx`
- 修改配置后想立即更新到域名托管商<br>
  把目录下的 `x.x.x.x`、`2???-x-x-x` 两文件名重命名为非当前的公网 IP 地址
  - 例如：当前 IPv4 公网地址为 `61.201.34.5`，则执行 `mv 61.201.34.5 1.1.1.1`
  - 例如：当前 IPv6 公网地址为 `240e-13-15-16`，则执行 `mv 240e-13-15-16 2-2-2-2-2`
  - 再次执行 `./main.sh 配置文件名`

## 许可证
auto-ddns 项目的许可协议 MIT 。更多信息参见 [LICENSE](https://gitee.com/HAN-workspace/auto-ddns/blob/main/license.md) 文件。
