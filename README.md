# iPhone 共享助手

Windows 家庭 SMB 共享管理工具。通过简洁的桌面界面选择本机文件夹、管理 SMB 共享，并为 iPhone“文件”App 提供可直接使用的 SMB 连接地址。

当前最终版本：**3.34**

## 项目定位

iPhone 共享助手面向家庭局域网文件访问场景，帮助用户快速共享照片、视频和文档文件夹，集中查看共享状态，并为 iPhone“文件”App 提供 SMB 连接地址。文件传输由 iPhone“文件”App 负责，软件本身不提供电脑端文件浏览器，也不上传文件到云端。

## 核心功能

- 扫描并显示本机 SMB 共享；
- 区分本软件管理的共享与外部/系统共享；
- 显示共享名称、本地路径、共享状态和访问权限；
- 新增共享文件夹；
- 暂停、恢复和删除本软件管理的共享；
- 暂停后保留共享记录，恢复时重新启用映射；
- 删除共享只移除 SMB 共享映射，不删除实际文件夹和文件；
- 支持直接打开本地共享文件夹；
- 支持复制完整的 iPhone SMB 地址；
- 长地址紧凑显示，悬停可查看完整内容；
- WPF 原生 Windows 桌面界面，默认深色模式。

## iPhone 连接方式

1. 在电脑上启动 iPhone 共享助手并完成共享；
2. 在 iPhone 上打开“文件”App；
3. 点击右上角“更多”按钮，选择“连接服务器”；
4. 输入软件提供的 `smb://` 地址；
5. 选择“注册用户”，输入 Windows 登录账号和密码；
6. 连接后即可访问共享文件夹。

电脑和 iPhone 必须连接到同一个局域网。Windows 防火墙、SMB 服务、共享权限或 NTFS 权限异常时，可能导致连接失败。

## 数据与安全

- 不保存 Windows 用户密码；
- 管理元数据保存在本机：`C:\ProgramData\iPhone共享助手\managed-shares.json`；
- 元数据仅记录共享名称、路径、来源、状态、创建时间和权限等管理信息；
- 不删除用户的实际文件夹和文件；
- 不自动删除未知共享；
- `C$`、`ADMIN$`、`IPC$` 等系统管理共享不会被误删；
- 修改 SMB、NTFS 权限或防火墙规则需要管理员权限；
- 建议仅在可信的家庭局域网中使用，不要将 SMB 端口暴露到公网。

## 运行源码

需要 Windows PowerShell 5.1 或更高版本，并以管理员权限运行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\源码\主程序-3.0.ps1"
```

## 下载最终版

- [下载 iPhone 共享助手 3.34](https://github.com/likailuo/iphone-share-assistant/releases/tag/v3.34)
- [直接下载 EXE](https://github.com/likailuo/iphone-share-assistant/releases/download/v3.34/iPhone.-3.34.exe)

## 构建项目

项目使用 PS2EXE 将 PowerShell 脚本打包为无控制台窗口的 Windows GUI 程序：

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\build.ps1"
```

也可以运行 `打包.bat`。构建输出位于 `打包输出\`，历史版本不会被覆盖。

## 测试

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\ui-layout.test.ps1"
```

提交修改前建议检查 PowerShell 语法、管理员权限拦截、共享扫描、暂停/恢复、删除保护、系统管理共享保护和构建脚本。

## 项目结构

```text
源码/主程序-3.0.ps1       主程序与 WPF 界面
资源/222.ico              程序图标
打包输出/iPhone共享助手-3.34.exe  最终版程序
docs/                     设计规格与实施计划
build.ps1                 PowerShell 构建脚本
打包.bat                  Windows 打包入口
ui-layout.test.ps1        UI 布局测试
开发进度.md               开发进度记录
```

## 许可证

当前仓库未声明开源许可证。除非仓库所有者另行授权，请不要将代码、图标或打包文件用于商业分发。