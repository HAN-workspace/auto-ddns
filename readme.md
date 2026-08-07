## 目录结构
<pre>auto-ddns/
    ├── readme.md
    ├── license.md （MIT License）
    ├── ddns-sh/
    │        ├── readme.md
    │        ├── main.sh       （主程序）
    │        ├── aliyun.sh     （阿里云 DNS API）
    │        ├── cloudflare.sh （Cloudflare DNS API）
    │        ├── example.com.cn（配置文件）
    │        ├── 1.1.1.1       （初始 IPv4 地址命名的文件）
    │        ├── 240e-1-1-1    （初始 IPv6 地址命名的文件）
    │        ├── info.log      （记录执行信息）
    │        └── changelog.md  （版本变更日志）
    ├── ddns-py/ （待办任务）
    │        └── ... 
    └── ddns-go/ （待办任务）
             └── ... 
</pre>
## 介绍
轻量级动态dns，实现自动调用 API 同步公网 IP 到域名托管商 ( 支持：阿里云 cloudflare  )<br>
支持 IPv4/6 动态公网地址，主机记录(A/AAAA)的增删改查。<br>
<font color="red">**重要：本脚本会接管所有子域名 (仅 A/AAAA 主机记录)，没有在配置文件中的将被删除。**</font>

## 软件架构
纯 linux bash 脚本，可运行于精简 bash 下，如 OpenWrt<br>
依赖 curl 及 openssl

## 安装教程
下载 [ddns-sh](https://github.com/HAN-workspace/auto-ddns/tree/main/ddns-sh)<br>
绿色脚本 无需安装 解压即用

## 使用说明
详细说明请参考 [ddns-sh 目录下的 readme.md](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md) 文件。
- 编写的属于你的[配置文件](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/example.com.cn) （该配置文件以你的域名名字命名）[查看配置文件示例](https://github.com/HAN-workspace/auto-ddns/blob/main/ddns-sh/readme.md#domain-%E5%86%85%E7%BB%93%E6%9E%84)
- 使主程序可运行  `chmod +x main.sh`
- 直接运行  `./main.sh “配置文件名”`
- 添加到任务让程序定时运行 `crontab -e` (可选)<br>
  粘贴 `*/5 * * * * /ddns-sh的绝对路径/main.sh 配置文件名`

## 技巧使用
- 多域名
  编写多个配置文件，每个配置文件以域名名字命名，如 `example.com.cn`、`example.net`、... 等
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh example.com.cn`
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh example.net`
  - 分别创建任务 `*/5 * * * * /ddns-sh的绝对路径/main.sh ...`
- 修改配置后想立即更新到域名托管商
  把目录下的 `x.x.x.x`、`2???-x-x-x` 等文件重名为非当前公网 IP
  - 例如：当前 IPv4 公网为 `61.201.34.5`，则执行 `mv 61.201.34.5 1.1.1.1` 等
  - 例如：当前 IPv6 公网为 `240e-13-15-16`，则执行 `mv 240e-13-15-16 2-2-2-2-2` 等
  - 再次执行 `./main.sh 配置文件名`

## 许可证
auto-ddns 项目的许可协议 MIT 。更多信息参见 [LICENSE](https://github.com/HAN-workspace/auto-ddns/blob/main/license.md) 文件。
