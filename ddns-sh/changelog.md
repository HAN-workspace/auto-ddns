## v1.1.0 (2026-08-8)

### 支持Cloudflare DNS 解释
- 新增 cloudflare.sh 脚本，用于更新 Cloudflare DNS 主机记录
- 支持配置文件中定义是否启用 “CF代理”(小橙云)
- main.sh 添加自动调用适配到的域名托管商API(只需在配置文件按规定配置即可)
- aliyun.sh 调整交互日志处理，添加了错误信息提示。
- OpenWrt 环境下，定时任务时不再产生误报的 cron.err 日志记录
  
## v1.0.0 (2026-07-28)

### 首次发布
- 纯 linux 脚本，兼容 OpenWrt 精简版 Bash
- 自动分析 IPv4/6 公网地址
- 支持阿里云 DNS 主机记录新增、删除、更新（仅支持 A、AAAA 类型）
- 只需按配置文件示例编写你的主机记录，简单快捷
- 支持自定义多个子域名，并可以自游定义A记录或AAAA记录

已知问题：
- OpenWrt 环境下，使用 crontab 定时任务时
  > 任务日志会记录："Tue Jul 28 21:20:00 2026 cron.err crond[3774]: USER root pid 24594 cmd /root/ddns-sh/main.sh example.com"<br>
  > <font style="background-color: #0066FF">不  影  响  系  统  稳  定  性  脚  本  执  行  无  异  常</font><br>
  > 为不让任务日志长期写入，请配置任务日志为“禁用(Disabled)” 或数值为 9 的选项
