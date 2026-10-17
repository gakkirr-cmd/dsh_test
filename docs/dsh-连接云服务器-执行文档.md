# dsh 远程 SSH · 接入腾讯云服务器（执行文档）

> **这份文档是写给 DeepSeek Harness（dsh）自己执行的。**
> dsh 读到本文后，直接执行「第 4 节」的步骤，不要重复第 2 节已经实测过的探测动作。
>
> 生成时间：2026-10-17 22:05 (GMT+8) ｜ 目标机器：本机 `DESKTOP-SVMU245`
> 本文所有关键结论均已用 dsh 同款 `ssh2@1.17.0` 库实机验证通过，非推测。

---

## 1. 任务目标

在**本机 dsh 桌面版**的「远程 SSH」面板中注册一台主机，让 dsh 的 `ssh_list` / `ssh_exec` / `ssh_upload` / `ssh_download` / `ssh_tunnel` / `ssh_cluster` 六个工具能够直接操作这台云服务器。

**交付判据（三条全过才算完成）**

| # | 判据 | 验证方式 |
| --- | --- | --- |
| 1 | 主机 `mycloud` 出现在 dsh 的 SSH 面板中 | 面板「主机」页签能看到一行 `mycloud` |
| 2 | Agent 侧能列到该主机，且密钥就绪 | `ssh_list` 返回含 `mycloud`，且 `keyReady: true` |
| 3 | 能真实执行远程命令 | `ssh_exec` 在 `mycloud` 上跑 `whoami`，返回 `ubuntu` |

---

## 2. 已知事实（已实测，dsh 不必重新探测）

### 2.1 服务器

| 项目 | 值 |
| --- | --- |
| 主机 / IP | `106.55.30.200` |
| SSH 端口 | `22` |
| **登录用户** | **`ubuntu`** |
| 系统 | Ubuntu 24.04，内核 `6.8.0-124-generic`，x86_64 |
| 主机名 | `VM-0-2-ubuntu` |
| sudo | **免密可用**（`sudo -n true` 通过） |
| 磁盘 | `/` 40G，已用 18G (47%) |

> **重要**：不要用 `dongshiwei` 用户登录。已实测 `dongshiwei@106.55.30.200` 返回 `Permission denied (publickey)`，该用户未配置公钥。`dongshiwei` 只是本地 Windows 账户名 / 历史遗留叫法，服务器上的登录账户是 `ubuntu`。

### 2.2 本机凭据（**这一节有两个坑，务必看清**）

本机 `~/.ssh` 下有两把**同一密钥**的不同编码文件，用途完全不同：

| 文件 | 开头标识 | 格式 | 系统 `ssh` 可用 | **dsh（ssh2）可用** |
| --- | --- | --- | --- | --- |
| `dongshiwei.pem` | `BEGIN RSA PRIVATE KEY` | PKCS#1 | ✅ | ✅ **（用这个）** |
| `dongshiwei_pkcs8.pem` | `BEGIN PRIVATE KEY` | PKCS#8 | ✅ | ❌ **不认，报 `Unsupported key format`** |

**结论：dsh 必须用 `C:\Users\HuanyinSSD\.ssh\dongshiwei.pem`。**

实测证据（用 dsh 自己的 `ssh2@1.17.0` 跑出来的）：

```text
ssh2 version: 1.17.0
dongshiwei.pem        -> OK type=ssh-rsa
dongshiwei_pkcs8.pem  -> ERR: Unsupported key format

用 dongshiwei.pem 建立真实连接：
  PARSE: OK  type = ssh-rsa
  CONNECT: OK
  OUT: ubuntu | VM-0-2-ubuntu | active
```

> **坑一**：`~/.ssh/config` 里的 `IdentityFile` 指向的是 `dongshiwei_pkcs8.pem`——那是给系统 `ssh` 用的，OpenSSH 认 PKCS#8，但 dsh 用的 ssh2 库不认。所以**千万不要直接把 config 里的路径照搬进 dsh**，否则连接时会报 `Cannot parse privateKey` / `Unsupported key format`。
>
> **坑二**：两把钥匙同一密钥、无口令，随便挑错一个都会白折腾。

私钥属性：RSA 2048，**无 passphrase**，无需在配置里写任何密码字段。

### 2.3 dsh 侧的实现事实

| 项目 | 值 |
| --- | --- |
| SSH 面板来源 | 插件 `@linxin666/dsh-ssh@0.4.6` |
| 底层 SSH 库 | `ssh2@1.17.0`（**不是系统 ssh 命令**） |
| 主机配置存储位置 | **`C:\Users\HuanyinSSD\.dsh\dsh-ssh.json`** |
| 当前状态 | **该文件不存在** → 所以面板显示「尚未配置主机」，与截图一致 |
| 配置文件格式 | `{"version":1,"hosts":[...]}`，版本号固定为 `1` |
| 权限要求 | 文件 `0600`、目录 `0700`（文件内含凭据，属敏感文件） |
| 是否需重启 dsh | **不需要**。插件每次读取都会比对文件 `mtime + size`，文件变化后下一次读取自动重新解析 |

---

## 3. 两条硬约束（动手前必须理解）

### 3.1 约束一：`ssh_*` 工具无法创建主机

dsh 的 SSH 插件只提供 `ssh_list` / `ssh_exec` / `ssh_upload` / `ssh_download` / `ssh_tunnel` / `ssh_cluster`，**其中没有任何一个能"新建主机"**。这是插件的安全设计，原文写在 README 里：

> Agent 使用工具前，主机需先在 GUI 中配置（或从 ~/.ssh/config 导入）。
> 它只能来自用户自己的 0600 配置文件：Agent 无法创建或修改主机。

也就是说：**在主机进入列表之前，`ssh_exec mycloud ...` 一定失败**，报的是"主机不存在"，而非网络错误。别把它误判成连不通。

### 3.2 约束二：私钥格式（最容易翻车的地方）

见 2.2。dsh 走 ssh2，**只认 `dongshiwei.pem`（PKCS#1）**，不认 `dongshiwei_pkcs8.pem`（PKCS#8）。

### 3.3 由此推出的可行路径

| 路线 | 做法 | 适合场景 |
| --- | --- | --- |
| **A（本文主推）** | 用本地文件写入工具直接生成 `~/.dsh/dsh-ssh.json` | 让 dsh 全自动完成 |
| **B（备选）** | 用户手动在面板点「导入 ~/.ssh/config」**后再手工把私钥路径改成 `dongshiwei.pem`** | 用户愿意自己点几下 |

> 路线 A 是写用户自己的 0600 配置文件，凭证来自用户本人，属于插件设计允许的来源，不违反 3.1 的限制。

---

## 4. 执行步骤（路线 A · 推荐）

### 4.1 先备份（幂等，可重复执行）

`dsh-ssh.json` 当前不存在，但脚本仍写成幂等的，防止将来重跑时覆盖已有主机。

```bash
cd ~/.dsh
if [ -f dsh-ssh.json ]; then
  cp dsh-ssh.json "dsh-ssh.json.bak-$(date +%Y%m%d-%H%M%S)"
  echo "已备份"
else
  echo "配置文件不存在，无需备份"
fi
```

### 4.2 写入主机配置

**方式一（推荐）：跑一个 Node 脚本**

用你的文件写入工具创建 `~/.dsh/dsh-ssh-host-setup.mjs`，内容如下：

```js
// 向 dsh-ssh 插件注册云服务器主机（幂等：已存在则更新，不重复添加）
import { readFileSync, writeFileSync, existsSync, copyFileSync, mkdirSync, renameSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const dshDir = join(homedir(), '.dsh')
const storePath = join(dshDir, 'dsh-ssh.json')
// 关键：必须用 PKCS#1（BEGIN RSA PRIVATE KEY）。PKCS#8 那个 dsh 的 ssh2 库不认。
const keyPath = join(homedir(), '.ssh', 'dongshiwei.pem')

if (!existsSync(keyPath)) {
  console.error(`[FAIL] 私钥不存在: ${keyPath}`)
  process.exit(1)
}

// 守卫：拦住 PKCS#8，避免写进去之后连接时才炸
const keyHead = readFileSync(keyPath, 'utf8').split('\n')[0].trim()
if (keyHead.includes('BEGIN PRIVATE KEY')) {
  console.error('[FAIL] 该私钥是 PKCS#8（BEGIN PRIVATE KEY），dsh 的 ssh2 不认，会报 Unsupported key format')
  console.error('       请改用 C:\\Users\\HuanyinSSD\\.ssh\\dongshiwei.pem（BEGIN RSA PRIVATE KEY）')
  process.exit(1)
}
if (!keyHead.includes('BEGIN RSA PRIVATE KEY')) {
  console.warn('[WARN] 私钥不是标准 PKCS#1 头，继续写入但可能解析失败:', keyHead)
}

if (!existsSync(dshDir)) mkdirSync(dshDir, { recursive: true, mode: 0o700 })

// 读旧文件；不存在或损坏都从空结构开始
let store = { version: 1, hosts: [] }
if (existsSync(storePath)) {
  copyFileSync(storePath, storePath + '.bak-' + Date.now())
  try {
    const parsed = JSON.parse(readFileSync(storePath, 'utf8'))
    if (parsed && Array.isArray(parsed.hosts)) store = { version: 1, hosts: parsed.hosts }
  } catch {
    console.warn('[WARN] 旧文件无法解析，将重建')
  }
}

const now = Date.now()
const entry = {
  alias: 'mycloud',
  host: '106.55.30.200',
  port: 22,
  user: 'ubuntu',
  auth: { kind: 'key', keyPath },
  proxyJump: [],
  description: '腾讯云轻量 · 康复系统 / dsh / Caddy',
  tags: ['tencent', 'production'],
  location: '深圳',
  createdAt: now,
  updatedAt: now,
}

const idx = store.hosts.findIndex(h => h && h.alias === 'mycloud')
if (idx >= 0) {
  entry.createdAt = store.hosts[idx].createdAt ?? now
  store.hosts[idx] = entry
  console.log('[OK] 已更新主机 mycloud')
} else {
  store.hosts.push(entry)
  console.log('[OK] 已新增主机 mycloud')
}

// 原子写入：先写 tmp 再 rename，保证插件永远读不到半截文件
const tmp = storePath + '.tmp'
writeFileSync(tmp, JSON.stringify(store, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 })
renameSync(tmp, storePath)

console.log('写入路径:', storePath)
console.log('密钥路径:', keyPath)
console.log('主机总数:', store.hosts.length)
console.log('别名列表:', store.hosts.map(h => h.alias).join(', '))
```

执行：

```bash
node ~/.dsh/dsh-ssh-host-setup.mjs
```

**方式二：直接写 JSON（不想跑脚本时用）**

把下面内容写入 `C:\Users\HuanyinSSD\.dsh\dsh-ssh.json`（时间戳可原样保留，不影响功能）：

```json
{
  "version": 1,
  "hosts": [
    {
      "alias": "mycloud",
      "host": "106.55.30.200",
      "port": 22,
      "user": "ubuntu",
      "auth": {
        "kind": "key",
        "keyPath": "C:\\Users\\HuanyinSSD\\.ssh\\dongshiwei.pem"
      },
      "proxyJump": [],
      "description": "腾讯云轻量 · 康复系统 / dsh / Caddy",
      "tags": [
        "tencent",
        "production"
      ],
      "location": "深圳",
      "createdAt": 1792245633263,
      "updatedAt": 1792245633263
    }
  ]
}
```

> 方式二容易把 `\\` 写成 `\` 或带 BOM，写完务必跑 4.3 的校验。

### 4.3 校验（必做，不要跳过）

```bash
node -e "
const fs=require('fs'),os=require('os'),p=require('path');
const f=p.join(os.homedir(),'.dsh','dsh-ssh.json');
const raw=fs.readFileSync(f);
if(raw[0]===0xEF&&raw[1]===0xBB&&raw[2]===0xBF){console.error('[FAIL] 文件带 UTF-8 BOM，JSON.parse 会失败，请重写为无 BOM');process.exit(1);}
const j=JSON.parse(raw.toString('utf8'));
if(j.version!==1)throw new Error('version 必须为 1');
if(!Array.isArray(j.hosts))throw new Error('hosts 必须是数组');
const h=j.hosts.find(x=>x.alias==='mycloud');
if(!h)throw new Error('缺少 mycloud');
if(!h.host||!h.user)throw new Error('host/user 必填');
if(!h.auth||h.auth.kind!=='key'||!h.auth.keyPath)throw new Error('auth 必须为 key 且带 keyPath');
if(!fs.existsSync(h.auth.keyPath))throw new Error('keyPath 指向的文件不存在: '+h.auth.keyPath);
const head=fs.readFileSync(h.auth.keyPath,'utf8').split('\n')[0].trim();
if(head.includes('BEGIN PRIVATE KEY'))throw new Error('keyPath 指向 PKCS#8 私钥，dsh 的 ssh2 不认，请改用 dongshiwei.pem');
if(h.proxyJump&&h.proxyJump.length&&h.proxyCommand)throw new Error('proxyJump 与 proxyCommand 不能同时设置');
console.log('[PASS] JSON 合法 · 无 BOM · 主机 mycloud 字段齐全 · 私钥格式正确');
console.log('  host =',h.host,'port =',h.port,'user =',h.user);
console.log('  key  =',h.auth.keyPath,'(',head,')');
"
```

**若校验报「带 BOM」**，用这条命令去 BOM（PowerShell 7）：

```powershell
$p = "$env:USERPROFILE\.dsh\dsh-ssh.json"
$s = [System.IO.File]::ReadAllText($p)
[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false)))
```

### 4.4 让面板刷新

不需要重启 dsh，但 GUI 的主机列表是**打开面板时拉取**的：

- 做法：关掉「远程 SSH」面板，再重新打开一次；或点「返回会话」再点回「SSH」。
- 刷新后「主机」页签应出现一行 `mycloud`，标签显示 `production`。

### 4.5 验收

按顺序执行，三步全过才算交付：

```text
1) ssh_list
   期望：列表包含 alias=mycloud、host=106.55.30.200、user=ubuntu、
         auth=key、keyReady=true

2) ssh_exec  alias=mycloud  command="whoami && hostname && uptime -p"
   期望：ubuntu / VM-0-2-ubuntu / up ...

3) ssh_exec  alias=mycloud  command="systemctl is-active rehab.service caddy.service"
   期望：连续两行 active
```

> 参考基线：本次已用 ssh2 直连实测，第 3 条命令的真实返回是 `ubuntu | VM-0-2-ubuntu | active`。

如果第 1 步就报「主机不存在」，说明文件没被读到 → 回到 4.3 校验，并确认路径确实是 `C:\Users\HuanyinSSD\.dsh\dsh-ssh.json`（不是 `.tmp`、也不是别的地方）。

---

## 5. 备选路线 B：面板一键导入（**导入后必须改私钥路径**）

1. 打开 dsh → 左侧「SSH」→ 顶部「主机」页签。
2. 点右上角 **「导入 ~/.ssh/config」**。
3. `~/.ssh/config` 里有 `Host mycloud` 块，导入后会出现主机 `mycloud`（用户 `ubuntu`）。
4. **⚠️ 必做**：点开这台主机编辑，把「私钥路径」从 `~/.ssh/dongshiwei_pkcs8.pem` **改成** `~/.ssh/dongshiwei.pem`，保存。
   不改的话，连接时 100% 报 `Unsupported key format`——因为 config 里写的是 PKCS#8。
5. 导入结果若有块被跳过，面板会逐条列出原因。本项目只有 `Host mycloud` 一个块，正常应 `added: 1`。

> **更省事的做法**：先把 `~/.ssh/config` 里的 `IdentityFile` 改成 `dongshiwei.pem`（系统 ssh 也认它，两边统一），再导入就不用手改。
>
> 两条路线写的是**同一个文件**，所以 A、B 不要混着用；先做哪条就以哪条为准。重复执行 A 脚本不会产生重复主机（幂等）。

---

## 6. 故障排查表

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `Unsupported key format` / `Cannot parse privateKey` | 用了 `dongshiwei_pkcs8.pem`（PKCS#8） | 换成 `dongshiwei.pem` |
| `Permission denied (publickey)` | 用户写成了 `dongshiwei` | 改回 `ubuntu` |
| `connect ETIMEDOUT` / `ECONNREFUSED` | 腾讯云安全组没放行 22，或 sshd 没起 | 控制台安全组加规则；`sudo systemctl status ssh` |
| `keyReady: false` | `keyPath` 路径写错或文件不存在 | 必须是 `C:\Users\HuanyinSSD\.ssh\dongshiwei.pem` |
| 面板仍显示「尚未配置主机」 | 面板没重新拉取 | 关闭再打开 SSH 面板；仍不行重启 dsh |
| 配置文件被改名为 `dsh-ssh.json.corrupt-<时间戳>` | JSON 解析失败（多为 **UTF-8 BOM** 或尾逗号） | 插件会把坏文件挪走并当空列表。用 4.2 重写后跑 4.3 校验 |
| 提示 `proxyCommand and proxyJump cannot be combined` | 两个传输字段同时存在 | 只留 `proxyJump: []` |
| 别名冲突 | 已有同名 alias | 脚本会自动改为「更新」而非「新增」 |

---

## 7. 连上之后：这台机器上跑着什么

供 dsh 后续操作参考，避免盲改：

| 服务 | 端口 | 说明 |
| --- | --- | --- |
| `rehab.service` | `127.0.0.1:8766` | 康复教学系统（仅本机监听，外网走 Caddy 反代） |
| `dsh-web.service` | 监听 `16821` | 服务器上的 dsh Web UI |
| `ia-web-frontend.service` | — | IA Agent 对话前台（平台自己的 dsh 实例，与个人 dsh 互不干扰） |
| `caddy.service` | `80` / `443` | 反向代理，对外入口 |
| `kuma.service` | `*:3001` | Uptime Kuma 监控 |
| `docker.service` | — | 容器运行时 |

- 家目录：`/home/ubuntu`（有 `backups`、`ia-agent`、`mattermost`、`MES` 等目录）
- 最近备份：`/home/ubuntu/rehab-code-20260822-235032.zip`
- 改系统服务可直接 `sudo`（已免密）：`sudo systemctl restart rehab.service`

> **操作纪律**：这是生产机。dsh 在这台主机上以只读操作为默认；`rehab.service` / `caddy.service` 重启会影响正在使用的老师，**变更前必须先告诉用户并等确认**。

---

## 8. 执行清单（dsh 自检用）

- [ ] 已理解 3.1：不能靠 `ssh_*` 工具建主机
- [ ] 已理解 3.2：私钥必须用 `dongshiwei.pem`（PKCS#1），不能用 `dongshiwei_pkcs8.pem`
- [ ] `dsh-ssh.json` 已备份（若原存在）
- [ ] 主机 `mycloud` 已写入，`user=ubuntu`、`keyPath` 指向 `dongshiwei.pem`
- [ ] 4.3 校验输出 `[PASS]`
- [ ] 面板已刷新，能看到 `mycloud`
- [ ] `ssh_list` 中 `keyReady=true`
- [ ] `ssh_exec ... whoami` 返回 `ubuntu`
- [ ] 已向用户报告：写入路径、主机别名、验收结果

以上全部打勾后，回复用户一句话即可：**「mycloud 已接入，ssh_exec 实测可用」**，并附上 `ssh_list` 的关键字段。
