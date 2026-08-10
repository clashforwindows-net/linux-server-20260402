# Linux 服务器管理教程 2026 — 运维实战手册

> 从**开机第一条命令**到**线上故障复盘**的完整实战路径。
> 不讲课本式的命令罗列，只讲 **在真实服务器上你会遇到什么、该敲什么、输出怎么读、下一步怎么办**。

![Linux](https://img.shields.io/badge/Linux-Server%20Ops-FCC624?logo=linux&logoColor=black)
![Distro](https://img.shields.io/badge/Debian%2012%20%7C%20Ubuntu%2024.04%20%7C%20Rocky%209-supported-brightgreen)
![Level](https://img.shields.io/badge/Level-入门到进阶-orange)

---

## 目录

- [第 0 章：新机到手的第一个小时](#第-0-章新机到手的第一个小时)
- [第 1 章：用户、权限与 sudo](#第-1-章用户权限与-sudo)
- [第 2 章：包管理与软件源](#第-2-章包管理与软件源)
- [第 3 章：systemd 服务管理](#第-3-章systemd-服务管理)
- [第 4 章：文件系统、磁盘与挂载](#第-4-章文件系统磁盘与挂载)
- [第 5 章：网络配置与防火墙](#第-5-章网络配置与防火墙)
- [第 6 章：性能调优（内核参数详解）](#第-6-章性能调优内核参数详解)
- [第 7 章：BBR 与网络加速](#第-7-章bbr-与网络加速)
- [第 8 章：SSH 深度配置](#第-8-章ssh-深度配置)
- [第 9 章：日志体系与轮转](#第-9-章日志体系与轮转)
- [第 10 章：定时任务](#第-10-章定时任务)
- [第 11 章：Shell 效率技巧](#第-11-章shell-效率技巧)
- [第 12 章：故障排查实战案例](#第-12-章故障排查实战案例)
- [第 13 章：命令速查表](#第-13-章命令速查表)
- [第 14 章：常见误操作与自救](#第-14-章常见误操作与自救)
- [FAQ](#faq)
- [仓库脚本与相关资源](#仓库脚本与相关资源)

---

## 第 0 章：新机到手的第一个小时

拿到一台全新 VPS，按这个顺序走，一小时后你会得到一台**可以安心跑业务的机器**。

### 0.1 先摸清家底

```bash
# 发行版与内核
cat /etc/os-release && uname -a

# CPU
lscpu | grep -E 'Model name|^CPU\(s\)|MHz|Virtualization|Hypervisor'

# 内存
free -h && cat /proc/meminfo | head -5

# 磁盘
lsblk -f && df -hT

# 虚拟化类型（KVM / OpenVZ / LXC 差别很大）
systemd-detect-virt

# 网络
ip -brief addr && ip route && cat /etc/resolv.conf
```

**为什么要先看虚拟化类型？**

| 类型 | 特点 | 影响 |
|------|------|------|
| KVM | 完整虚拟化，独立内核 | 可改内核参数、可装 BBR、可跑 Docker |
| OpenVZ / LXC | 共享宿主内核 | **不能改内核、不能装 BBR、swap 常不可用** |

如果 `systemd-detect-virt` 输出 `openvz` 或 `lxc`，那本文第 6、7 章的很多内容你都用不了，建议换 KVM 机器。

### 0.2 更新系统 + 装基础工具

```bash
# Debian / Ubuntu
apt update && apt full-upgrade -y
apt install -y curl wget vim git htop ncdu tree jq unzip \
               net-tools dnsutils mtr-tiny tcpdump lsof \
               sysstat iotop iftop vnstat rsync tmux

# Rocky / AlmaLinux
dnf update -y
dnf install -y epel-release
dnf install -y curl wget vim git htop ncdu tree jq unzip \
               bind-utils mtr tcpdump lsof sysstat iotop \
               iftop vnstat rsync tmux
```

### 0.3 时区与时间同步

```bash
timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true
timedatectl status
```

**时间不同步会导致：** TLS 证书校验失败、日志时间错乱、分布式锁失效、TOTP 二次验证登录不了。这不是小事。

### 0.4 主机名

```bash
hostnamectl set-hostname web-hk-01
# 同步写入 hosts，否则 sudo 会有解析延迟
grep -q "$(hostname)" /etc/hosts || echo "127.0.1.1 $(hostname)" >> /etc/hosts
```

### 0.5 创建运维账户（不要一直用 root）

```bash
useradd -m -s /bin/bash ops
usermod -aG sudo ops                    # Debian 系
# usermod -aG wheel ops                 # RHEL 系
mkdir -p /home/ops/.ssh && chmod 700 /home/ops/.ssh
echo 'ssh-ed25519 AAAA...your-key' > /home/ops/.ssh/authorized_keys
chmod 600 /home/ops/.ssh/authorized_keys
chown -R ops:ops /home/ops/.ssh

# 免密 sudo（可选，自动化场景需要）
echo 'ops ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ops
chmod 440 /etc/sudoers.d/ops
visudo -c        # 一定要校验语法！改坏 sudoers 会让你彻底失去 sudo
```

### 0.6 Swap（小内存机器必备）

```bash
# 1G 内存机器建议 2G swap
fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 降低使用倾向：优先用物理内存，实在不够才用 swap
sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' >> /etc/sysctl.d/99-tuning.conf
```

**swappiness 取值建议：**

| 值 | 场景 |
|:--:|------|
| 0 | 几乎不用 swap（内存充足的数据库） |
| 10 | **推荐值**，小内存 VPS |
| 60 | 系统默认，桌面适用 |

### 0.7 检查清单

```
[ ] 系统已更新
[ ] 时区/NTP 正确
[ ] 主机名已设置
[ ] 非 root 账户 + SSH 公钥已配置且**已验证能登录**
[ ] Swap 已启用（如需要）
[ ] SSH 已加固（见第 8 章）
[ ] 防火墙规则已配置（见第 5 章）
[ ] 自动安全更新已开启
[ ] 备份/快照策略已确认
```

---

## 第 1 章：用户、权限与 sudo

### 1.1 权限位理解

```bash
$ ls -l /etc/shadow
-rw-r----- 1 root shadow 1523 Aug 10 21:00 /etc/shadow
 │└┬┘└┬┘└┬┘
 │ │  │  └── other: ---（无权限）
 │ │  └───── group: r--（shadow 组可读）
 │ └──────── owner: rw-（root 可读写）
 └────────── 文件类型：- 普通文件, d 目录, l 链接
```

```bash
chmod 755 script.sh      # rwxr-xr-x
chmod 600 id_rsa         # rw------- 私钥必须是这个
chmod 700 ~/.ssh         # drwx------
chmod u+x,go-w file      # 符号方式
chown -R www-data:www-data /var/www
```

### 1.2 特殊权限位

```bash
# SUID：以文件所有者身份运行（passwd 命令就靠这个）
chmod u+s /usr/bin/somecmd     # 危险，慎用

# SGID：目录内新建文件继承目录的组
chmod g+s /shared/team

# Sticky bit：只有文件所有者能删除（/tmp 就是这样）
chmod +t /tmp
```

**安全审计必查项 —— 找出异常的 SUID 文件：**

```bash
find / -xdev -perm -4000 -type f -exec ls -l {} \; 2>/dev/null
```

### 1.3 sudo 精细化授权

```bash
# /etc/sudoers.d/deploy
# 只允许执行特定命令，最小权限原则
deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart myapp, \
                           /bin/systemctl status myapp, \
                           /usr/bin/docker compose -f /opt/app/compose.yml *
```

```bash
# 查看某用户能执行什么
sudo -l -U deploy

# sudo 操作审计日志
grep sudo /var/log/auth.log | tail -20
```

---

## 第 2 章：包管理与软件源

### 2.1 apt 常用操作

```bash
apt update                    # 更新索引
apt list --upgradable         # 看看有什么可升级
apt full-upgrade -y           # 完整升级（会处理依赖变化）
apt install --no-install-recommends pkg   # 不装推荐包，省空间
apt-mark hold nginx           # 锁定版本不升级
apt autoremove --purge -y     # 清理孤立包及配置
apt clean                     # 清缓存

# 查一个文件属于哪个包
dpkg -S /usr/bin/curl
# 查包里有哪些文件
dpkg -L curl
# 查未安装的包里有什么文件
apt-file search bin/htop
```

### 2.2 换镜像源（国内机器提速关键）

```bash
# Debian 12
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.aliyun.com/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF
apt update
```

> 💡 **境外 VPS 不要换国内源**，反而会更慢。国外机器用官方源或就近的镜像（如 `deb.debian.org` 自带 CDN）即可。

### 2.3 自动安全更新

```bash
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# 只自动装安全更新，不动其他包
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
```

---

## 第 3 章：systemd 服务管理

### 3.1 基本操作

```bash
systemctl start|stop|restart|reload nginx
systemctl enable --now nginx        # 开机自启 + 立即启动
systemctl disable --now nginx
systemctl status nginx -l --no-pager
systemctl is-active nginx           # 脚本里判断用
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled
systemctl daemon-reload             # 改了 unit 文件后必须执行
```

> `restart` 和 `reload` 的区别：`reload` 是发 `SIGHUP` 让服务重读配置**不中断连接**，`restart` 会真的杀掉重启。nginx / sshd 优先用 `reload`。

### 3.2 写一个规范的 unit 文件

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
Documentation=https://example.com/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=/opt/myapp
EnvironmentFile=-/etc/myapp/env
ExecStart=/opt/myapp/bin/server --config /etc/myapp/config.yml
ExecReload=/bin/kill -HUP $MAINPID

# 自动重启策略
Restart=on-failure
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=120

# 资源限制（很重要，防止一个服务拖垮整机）
LimitNOFILE=65535
MemoryMax=1G
CPUQuota=150%

# 安全沙箱
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/myapp/data /var/log/myapp

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now myapp
journalctl -u myapp -f
```

### 3.3 排查启动失败

```bash
systemctl status myapp -l
journalctl -u myapp -n 100 --no-pager
systemd-analyze verify /etc/systemd/system/myapp.service

# 开机耗时分析
systemd-analyze
systemd-analyze blame | head -15
systemd-analyze critical-chain
```

---

## 第 4 章：文件系统、磁盘与挂载

### 4.1 挂载新数据盘

```bash
lsblk                              # 找到新盘，比如 /dev/vdb
mkfs.ext4 -L data /dev/vdb         # 或 mkfs.xfs
mkdir -p /data
blkid /dev/vdb                     # 拿 UUID

# 写 fstab（**一定用 UUID，不要用 /dev/vdb**，设备名会变）
echo 'UUID=xxxx-xxxx /data ext4 defaults,noatime 0 2' >> /etc/fstab
mount -a && df -h /data
```

> ⚠️ **改完 fstab 一定要 `mount -a` 验证**。写错了机器重启会卡在 emergency mode，只能靠 VNC 救。

`noatime` 挂载选项：禁用访问时间更新，**能明显减少小文件场景的写入量**，几乎无副作用，强烈建议加上。

### 4.2 常用磁盘操作

```bash
df -hT                             # 空间 + 文件系统类型
df -i                              # inode 使用率
ncdu -x /                          # 交互式找大目录
du -x -h --max-depth=2 /var | sort -rh | head
lsblk -f                           # 分区与文件系统树
findmnt                            # 挂载点树形展示

# 扩容（云盘扩容后）
growpart /dev/vda 1
resize2fs /dev/vda1                # ext4
xfs_growfs /                       # xfs
```

### 4.3 文件系统检查与修复

```bash
# 必须先卸载
umount /data
fsck -y /dev/vdb

# 根分区需要重启时检查
touch /forcefsck && reboot
```

---

## 第 5 章：网络配置与防火墙

### 5.1 iproute2 命令

```bash
ip -brief addr                     # 简洁 IP 列表
ip addr add 10.0.0.5/24 dev eth0
ip route                           # 路由表
ip route add 10.1.0.0/16 via 10.0.0.1
ip -s link show eth0               # 收发包统计与错误
ip neigh                           # ARP 表
```

### 5.2 静态 IP（netplan / Ubuntu）

```yaml
# /etc/netplan/01-static.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.1.100/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

```bash
netplan try        # 有超时回滚保护，比 netplan apply 安全
```

### 5.3 防火墙：ufw（简单）

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22022/tcp comment 'SSH'
ufw allow 80,443/tcp comment 'Web'
ufw limit 22022/tcp             # 限速，防暴力破解
ufw enable
ufw status numbered
ufw delete 3
```

### 5.4 防火墙：nftables（现代方案）

```bash
# /etc/nftables.conf
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop
    iif lo accept
    ip protocol icmp accept
    tcp dport { 22022, 80, 443 } accept
    # SSH 限速：每分钟最多 6 个新连接
    tcp dport 22022 ct state new limit rate 6/minute accept
    log prefix "nft-drop: " limit rate 5/minute
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy accept; }
}
```

```bash
nft -f /etc/nftables.conf
systemctl enable --now nftables
nft list ruleset
```

> ⚠️ **改防火墙前一定先开一个"保险丝"**：
> ```bash
> # 15 分钟后自动清空规则，改坏了不至于把自己关外面
> echo 'nft flush ruleset' | at now + 15 minutes
> ```
> 确认新规则没问题后 `atrm` 取消这个任务。

---

## 第 6 章：性能调优（内核参数详解）

### 6.1 完整调优配置

```bash
cat > /etc/sysctl.d/99-server-tuning.conf <<'EOF'
### 文件句柄 ###
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

### 连接队列 ###
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 32768

### 缓冲区 ###
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_mem = 786432 1048576 26777216

### TIME_WAIT 与端口 ###
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.ip_local_port_range = 1024 65535

### 保活与 SYN ###
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3

### 拥塞控制 ###
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

### 转发（代理/网关场景）###
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

### 内存 ###
vm.swappiness = 10
vm.overcommit_memory = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536

### 安全 ###
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.randomize_va_space = 2
EOF

sysctl --system
```

### 6.2 逐条说明（别盲抄）

| 参数 | 作用 | 什么时候需要 |
|------|------|-------------|
| `somaxconn` | accept 队列上限 | 高并发 Web，默认 4096 太小 |
| `tcp_max_syn_backlog` | 半连接队列 | 抗 SYN Flood |
| `tcp_tw_reuse` | 复用 TIME_WAIT | 短连接密集（如反代后端） |
| `tcp_slow_start_after_idle=0` | 空闲后不降窗 | **长连接场景提速明显** |
| `tcp_mtu_probing=1` | 自动探测 MTU | 隧道/VPN 场景防黑洞 |
| `vm.dirty_ratio` | 脏页占比上限 | 调低可减少写入尖峰卡顿 |
| `default_qdisc=fq` | 公平队列 | **BBR 的前置依赖** |

> ❌ **不要设置 `net.ipv4.tcp_tw_recycle`**。它在 NAT 后会丢弃时间戳乱序的包，导致大量连接失败，Linux 4.12+ 已彻底移除。网上大量老教程还在推荐这个，是错的。

### 6.3 文件句柄限制

```bash
cat > /etc/security/limits.d/99-nofile.conf <<'EOF'
*    soft nofile 65535
*    hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# systemd 服务不读 limits.conf，要单独配
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=65535
EOF
systemctl daemon-reexec
```

验证：

```bash
ulimit -n
cat /proc/$(pgrep -f nginx | head -1)/limits | grep 'open files'
```

---

## 第 7 章：BBR 与网络加速

### 7.1 检查与启用

```bash
# 内核 >= 4.9 即内置 BBR
uname -r

# 查看可用算法
sysctl net.ipv4.tcp_available_congestion_control

# 启用
cat >> /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system

# 验证
sysctl net.ipv4.tcp_congestion_control     # 应输出 bbr
lsmod | grep bbr
```

### 7.2 BBR 效果与适用场景

| 场景 | BBR 提升 | 说明 |
|------|:--------:|------|
| 高延迟高丢包国际链路 | ⭐⭐⭐⭐⭐ | 提升最明显，常见 2-5 倍 |
| 国内低延迟链路 | ⭐⭐ | 本来就不丢包，提升有限 |
| 大文件下载 | ⭐⭐⭐⭐ | 明显 |
| 小请求高并发 API | ⭐ | 几乎无感 |

**原理一句话**：传统 CUBIC 把"丢包"当拥塞信号，在高丢包的国际链路上会疯狂降速；BBR 通过主动测量**带宽和 RTT** 来决定发送速率，不被偶发丢包误导。

### 7.3 测速验证

```bash
# 官方 speedtest
curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -

# 简单下载测速
curl -o /dev/null -w '%{speed_download}\n' \
  http://speedtest.tokyo.linode.com/100MB-tokyo.bin

# 前后对比要在同一时段、同一目标测，否则没有意义
```

---

## 第 8 章：SSH 深度配置

### 8.1 生成与部署密钥

```bash
# 本地生成（ed25519 比 RSA 更短更安全）
ssh-keygen -t ed25519 -C "ops@laptop" -f ~/.ssh/id_ed25519

# 部署到服务器
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 22 ops@server
```

### 8.2 加固 sshd_config

```
Port 22022
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ops
X11Forwarding no
AllowAgentForwarding no
PermitEmptyPasswords no
UseDNS no
GSSAPIAuthentication no
```

**安全流程（防止把自己锁在外面）：**

```bash
cp /etc/ssh/sshd_config{,.bak}
vim /etc/ssh/sshd_config
sshd -t                        # 语法检查，必做
systemctl reload sshd
# ⚠️ 不要关掉当前会话！另开一个终端验证能登录成功后再关
ssh -p 22022 ops@server
```

### 8.3 客户端体验优化

```
# ~/.ssh/config
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
    AddKeysToAgent yes
    HashKnownHosts yes

Host hk1
    HostName 1.2.3.4
    Port 22022
    User ops
    IdentityFile ~/.ssh/id_ed25519

# 通过跳板机访问内网
Host internal-db
    HostName 10.0.1.20
    ProxyJump hk1
```

### 8.4 端口转发速查

```bash
# 本地转发：把远程 3306 映射到本地 13306
ssh -L 13306:127.0.0.1:3306 -N -f hk1

# 远程转发：把本地 8080 暴露到远程 9090
ssh -R 9090:127.0.0.1:8080 -N -f hk1

# 动态转发（SOCKS5 代理）
ssh -D 1080 -N -f hk1
```

---

## 第 9 章：日志体系与轮转

### 9.1 journald

```bash
journalctl -u nginx -f
journalctl --since "2026-08-10 20:00" --until "2026-08-10 22:00"
journalctl -p err -b                  # 本次启动的错误
journalctl -b -1                      # 上次启动（排查异常重启）
journalctl --disk-usage
journalctl --vacuum-time=14d
journalctl --vacuum-size=500M
```

持久化配置（默认某些系统重启后日志就没了）：

```
# /etc/systemd/journald.conf
[Journal]
Storage=persistent
SystemMaxUse=500M
MaxRetentionSec=30day
Compress=yes
```

### 9.2 logrotate

```
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 14
    size 100M
    compress
    delaycompress
    missingok
    notifempty
    create 0640 appuser adm
    sharedscripts
    postrotate
        systemctl reload myapp >/dev/null 2>&1 || true
    endscript
}
```

```bash
logrotate -d /etc/logrotate.d/myapp    # 演练，不实际执行
logrotate -f /etc/logrotate.d/myapp    # 强制执行一次
```

> 💡 `copytruncate` vs `postrotate reload`：前者会有极短的日志丢失窗口但不用重载服务；后者更精确但要求服务支持信号重开日志。**能用 postrotate 就别用 copytruncate**。

---

## 第 10 章：定时任务

### 10.1 crontab

```bash
crontab -e              # 编辑当前用户
crontab -l              # 查看
crontab -u ops -l       # 查看指定用户
```

```cron
# 分 时 日 月 周  命令
*/5  *  *  *  *  /opt/scripts/health.sh
0    3  *  *  *  /opt/scripts/backup.sh
0    4  *  *  0  /opt/scripts/weekly.sh
@reboot          /opt/scripts/on-boot.sh
```

**三大坑：**

```cron
# 坑1：PATH 不同 —— 顶部显式声明
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash

# 坑2：% 是特殊字符，必须转义
0 3 * * * echo "$(date +\%Y-\%m-\%d)" >> /tmp/d.log

# 坑3：没有输出重定向，出错了你永远不知道
0 3 * * * /opt/scripts/backup.sh >> /var/log/backup.log 2>&1
```

### 10.2 systemd timer（更推荐）

```bash
systemctl list-timers --all
journalctl -u backup.service --since today
```

相比 cron 的优势：错过的任务开机会补跑（`Persistent=true`）、日志统一进 journald、可以设置随机延迟避免多机同时打爆下游。

---

## 第 11 章：Shell 效率技巧

### 11.1 必备快捷键

| 快捷键 | 作用 |
|--------|------|
| `Ctrl+R` | 反向搜索历史命令（最有用的一个） |
| `Ctrl+A` / `Ctrl+E` | 行首 / 行尾 |
| `Ctrl+W` | 删除前一个单词 |
| `Ctrl+U` / `Ctrl+K` | 删到行首 / 行尾 |
| `Ctrl+L` | 清屏 |
| `Alt+.` | 插入上条命令的最后一个参数 |
| `Ctrl+Z` → `bg` / `fg` | 挂起 / 后台 / 前台 |

### 11.2 好用的 bashrc

```bash
cat >> ~/.bashrc <<'EOF'
# 历史
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTTIMEFORMAT='%F %T '
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend cmdhist checkwinsize

# 别名
alias ll='ls -alhF --color=auto'
alias ..='cd ..'
alias grep='grep --color=auto'
alias df='df -hT'
alias du='du -h'
alias ports='ss -tulnp'
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias psmem='ps -eo pid,comm,rss --sort=-rss | head -15'
alias pscpu='ps -eo pid,comm,%cpu --sort=-%cpu | head -15'
alias myip='curl -s ifconfig.me; echo'
alias jctl='journalctl -xe --no-pager'

# 安全网
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# 快速解压
extract() {
  case "$1" in
    *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.xz)       tar xJf "$1" ;;
    *.tar.bz2)      tar xjf "$1" ;;
    *.zip)          unzip "$1"   ;;
    *.gz)           gunzip "$1"  ;;
    *) echo "不支持的格式: $1" ;;
  esac
}
EOF
source ~/.bashrc
```

### 11.3 高频一行命令

```bash
# 端口占用
ss -tulnp | grep :443

# 查找并删除 30 天前的日志
find /var/log -name '*.log.*' -mtime +30 -delete

# 批量替换
grep -rl 'old_domain' /etc/nginx/ | xargs sed -i 's/old_domain/new_domain/g'

# 统计目录下文件数
find . -type f | wc -l

# 找出最近修改过的文件（排查被改了什么）
find /etc -mmin -60 -type f 2>/dev/null

# 实时看某个目录大小变化
watch -n2 'du -sh /var/log'

# 生成随机强密码
openssl rand -base64 24

# 快速起个 HTTP 服务传文件
python3 -m http.server 8000
```

---

## 第 12 章：故障排查实战案例

### 案例 1：服务器"卡死"，SSH 都连不上

**症状**：ping 通，SSH 连接后卡住不给 shell。

```bash
# 通过厂商 VNC 进入
uptime                     # load 高达 80
vmstat 1 5                 # b 列一堆，wa 90%+
iostat -x 1                # await 3000ms，%util 100%
iotop -oPa                 # 某个 mysqldump 在疯狂读盘
```

**原因**：备份任务和业务高峰撞车，磁盘被打满。
**解决**：备份加 `ionice -c3`（idle 优先级）+ 挪到低峰期。

```bash
ionice -c3 nice -n19 mysqldump ... 
```

### 案例 2：`No space left on device` 但 df 显示还有空间

```bash
df -h    # 60% 使用率
df -i    # inode 100%  ← 就是它
find / -xdev -type f | awk -F/ '{print "/"$2"/"$3}' | sort | uniq -c | sort -rn | head
# → /var/spool/postfix 里有 200 万个小文件
```

**原因**：邮件队列堆积/session 文件没清理。
**解决**：清理小文件；长期方案是给该目录单独分区或改用 XFS（动态 inode）。

### 案例 3：Nginx 报 `Too many open files`

```bash
cat /proc/$(pgrep -f 'nginx: master')/limits | grep 'open files'
# → Max open files  1024  1024
```

**原因**：改了 `/etc/security/limits.conf` 但 systemd 服务不读它。
**解决**：在 unit 里加 `LimitNOFILE=65535`，`daemon-reload` + `restart`（**reload 不生效，必须 restart**）。

### 案例 4：定时任务手动能跑，cron 里不跑

```bash
grep CRON /var/log/syslog | tail -20
# → command not found: docker
```

**原因**：cron 的 PATH 只有 `/usr/bin:/bin`。
**解决**：crontab 顶部加 `PATH=`，或脚本内用绝对路径。

### 案例 5：机器莫名重启

```bash
last -x | head -10                       # 看重启记录
journalctl -b -1 -p err --no-pager       # 上次启动的错误
dmesg -T | grep -iE 'oom|panic|hardware'
uptime                                    # 确认重启时间
```

三种常见原因：OOM 触发内核 panic、宿主机故障/迁移、服务商因欠费或滥用检测重启。查 `journalctl -b -1` 的最后几行通常能定位。

---

## 第 13 章：命令速查表

### 系统信息

```bash
uname -a               # 内核版本
cat /etc/os-release    # 发行版
hostnamectl            # 主机信息汇总
uptime                 # 运行时长与负载
lscpu / lsmem / lsblk / lspci / lsusb
systemd-detect-virt    # 虚拟化类型
timedatectl            # 时间与时区
```

### 进程

```bash
ps aux --sort=-%mem | head
pgrep -a nginx
pkill -f 'python app.py'
kill -15 PID           # 优雅退出（先试这个）
kill -9 PID            # 强杀（最后手段）
nohup cmd &            # 后台运行
jobs / fg / bg
nice -n 10 cmd         # 降低优先级
renice -n 10 -p PID
```

### 文件

```bash
find /path -name '*.log' -mtime +7 -size +100M
find . -type f -exec grep -l 'pattern' {} +
tar czf out.tar.gz dir/ && tar xzf out.tar.gz
rsync -avz --delete src/ dst/
ln -s /target /link
stat file              # 详细元信息
file unknown_binary    # 判断文件类型
md5sum / sha256sum
```

### 文本处理

```bash
awk '{print $1, $9}' access.log
awk -F: '$3>=1000 {print $1}' /etc/passwd
sed -i 's/old/new/g' file
sed -n '10,20p' file
cut -d, -f1,3 data.csv
sort -u | uniq -c | sort -rn
tr -s ' ' | column -t
jq '.items[] | .name' data.json
```

### 网络

```bash
ss -tulnp
ip -brief addr
curl -I https://example.com
curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' URL
wget -c URL            # 断点续传
dig +short example.com
mtr -rwc 50 target
nc -zv host port
```

---

## 第 14 章：常见误操作与自救

| 误操作 | 后果 | 自救方法 |
|--------|------|----------|
| `chmod -R 777 /` | 系统全乱，sudo/ssh 失效 | 基本只能重装，或从快照恢复 |
| 改坏 `/etc/sudoers` | 无法 sudo | `pkexec visudo` 或单用户模式修复 |
| 改坏 `/etc/fstab` | 启动卡 emergency | VNC 进入，`mount -o remount,rw /` 后改回 |
| 关掉 SSH 密码登录但没配密钥 | 登不上 | VNC 控制台改回 |
| 防火墙默认 DROP 忘了放 SSH | 登不上 | VNC，或提前设 `at` 定时清规则 |
| `rm -rf` 删错目录 | 数据没了 | ext4 用 `extundelete` 试试，最好还是有备份 |
| 磁盘写满导致服务挂 | 全站 502 | 先删日志救急，再查根因 |

**三条保命建议：**

1. **任何危险操作前先做快照**，云厂商快照通常几块钱一个月，比重装省事一万倍。
2. **改网络/SSH/防火墙前先设一个 `at` 定时回滚任务**，确认没问题再取消。
3. **`rm` 前先 `ls` 一遍同样的路径**，或者用 `trash-cli` 代替 `rm`。

---

## FAQ

**Q1：Debian 还是 Ubuntu 还是 Rocky？**
服务器场景：Debian 稳定精简（推荐）；Ubuntu LTS 生态好文档多；Rocky/Alma 适合需要 RHEL 兼容的企业环境。新手用 Debian 12 或 Ubuntu 22.04/24.04 LTS 最省心。

**Q2：为什么我的 VPS 装不了 BBR？**
大概率是 OpenVZ/LXC 架构，共享宿主内核，改不了拥塞算法。`systemd-detect-virt` 确认一下，是的话只能换 KVM 机器。

**Q3：1 核 512M 的小机器能跑什么？**
静态站点、小型反代、单个 Telegram Bot 没问题。跑 MySQL + PHP 就很吃力了，一定要配 swap。建议至少 1G 内存起步。

**Q4：为什么 `free` 显示内存几乎用光？**
`buff/cache` 是可回收的页缓存，看 `available` 才对。Linux 不用白不用，空着的内存才是浪费。

**Q5：应该关闭 SELinux 吗？**
不建议直接关。先用 `setenforce 0` 临时切 permissive 排查，用 `ausearch -m avc -ts recent` 看拦截了什么，再用 `semanage`/`setsebool` 精确放行。一关了之等于放弃一层防护。

**Q6：日志占满磁盘怎么预防？**
三件事：`journald` 配 `SystemMaxUse`、给应用日志配 `logrotate`、加磁盘使用率告警（80% 就提醒）。

**Q7：怎么判断 VPS 是不是被超售了？**
看 `vmstat 1` 的 `st`（steal）列。长期 > 10% 说明宿主机 CPU 被邻居抢走。再配合 `fio` 测磁盘 P99 延迟。实测数据可参考 [vpsvip.net](https://vpsvip.net)。

**Q8：需要装宝塔/1Panel 这类面板吗？**
新手可以，能少踩很多坑。但面板会开额外端口、装一堆你不需要的组件。真要用请务必改默认端口、开 IP 白名单、及时更新。

---

## 仓库脚本与相关资源

### 本仓库脚本

| 脚本 | 用途 | 用法 |
|------|------|------|
| `bench.sh` | 综合性能测试（CPU/内存/磁盘/网络） | `sudo ./bench.sh` |
| `bbr.sh` | 一键检测并启用 BBR + fq | `sudo ./bbr.sh` |
| `ssh-hardening.sh` | SSH 安全加固（含回滚保护） | `sudo ./ssh-hardening.sh --port 22022` |
| `sysctl-tune.sh` | 应用第 6 章的内核调优参数 | `sudo ./sysctl-tune.sh` |
| `init-server.sh` | 第 0 章全流程自动化 | `sudo ./init-server.sh --hostname web-01` |
| `quick-diag.sh` | 60 秒系统体检 | `./quick-diag.sh` |

### 使用

```bash
git clone https://github.com/clashforwindows-net/linux-server-20260402.git
cd linux-server-20260402
chmod +x *.sh
sudo ./bench.sh
```

### 本组织相关仓库

| 仓库 | 说明 |
|------|------|
| [vps-scripts](https://github.com/clashforwindows-net/vps-scripts) | 自动化运维脚本库（备份/部署/告警） |
| [vps-tools](https://github.com/clashforwindows-net/vps-tools) | 诊断工具集与排查方法论 |
| [server-monitoring](https://github.com/clashforwindows-net/server-monitoring) | Prometheus + Grafana 监控方案 |
| [vps-security-20260327](https://github.com/clashforwindows-net/vps-security-20260327) | 安全加固完全手册 |
| [vps-bench-20260327](https://github.com/clashforwindows-net/vps-bench-20260327) | VPS 性能测试与评分体系 |

### 服务器选购

调优能榨出 20% 性能，但选错机器损失的是 200%。选机重点看：虚拟化类型（认准 KVM）、CPU steal 时间、磁盘 P99 延迟、回程路由。

- 🖥️ **VPS 评测与推荐**：[https://vpsvip.net](https://vpsvip.net)
- 🚀 **网络加速方案**：[ClashVIP](https://clashvip.net)
- 🧭 **工具资源导航**：[nav.clashvip.net](https://nav.clashvip.net)

### 关键词

`Linux服务器教程` `VPS运维` `systemd` `sysctl调优` `BBR加速` `SSH加固` `nftables防火墙` `logrotate` `crontab` `故障排查` `内核参数` `Debian` `Ubuntu` `Rocky Linux` `服务器初始化` `运维手册`

---

## 免责声明

本文所有命令均会修改系统状态。请在测试环境验证后再用于生产，并提前做好快照。使用者需自行承担操作风险，并遵守当地法律法规与服务商条款。

**License**: MIT

---

*最后更新: 2026-08-10 | 维护者: clashforwindows-net | 推荐: [VPSVIP](https://vpsvip.net)*
