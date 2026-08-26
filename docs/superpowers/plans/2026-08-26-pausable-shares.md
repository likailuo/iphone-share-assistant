# 可暂停共享与管理记录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本软件创建的 SMB 共享支持暂停、恢复和删除管理记录，并在暂停后继续显示在列表中。

**Architecture:** 在现有单文件 PowerShell/WPF 程序中加入一个受保护的 ProgramData JSON 元数据层。列表由“实时 SMB 共享扫描结果”与“本软件元数据”合并得到；暂停只移除 SMB 映射，恢复按元数据重建映射，删除同时移除映射和元数据但不触碰文件夹。

**Tech Stack:** Windows PowerShell 5.1、WPF、SmbShare、JSON 文件、现有 `ui-layout.test.ps1` 静态回归测试。

**Spec:** `docs/superpowers/specs/2026-08-26-pausable-shares-spec.md`

## Global Constraints

- 所有 SMB、NTFS、服务和防火墙修改继续要求管理员权限。
- 不保存 Windows 用户密码，不自动删除文件夹、文件或未知用户。
- 元数据文件固定为 `C:\ProgramData\iPhone共享助手\managed-shares.json`。
- 外部共享和系统管理共享不进入本软件暂停记录；系统共享不可关闭。
- 关闭/删除确认必须明确说明不会删除实际文件夹和文件。

### Task 1: Metadata storage and merged share model

**Files:**
- Modify: `源码/主程序-3.0.ps1:9-218`
- Modify: `ui-layout.test.ps1`
- Test: `ui-layout.test.ps1`

**Interfaces:**
- Add `Get-ManagedMetadata`, `Save-ManagedMetadata`, `Get-ManagedRecord`, `Set-ManagedRecord`, `Remove-ManagedRecord`.
- Extend `Get-ShareRows` so it returns live and paused managed records with `Managed`, `Paused`, `CreatedAt`, and `AccessLines` fields.

- [ ] **Step 1: Write failing assertions** for the metadata path, JSON helpers, paused merge state, and no-password field.
- [ ] **Step 2: Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ui-layout.test.ps1` and verify it fails because the metadata layer is absent.
- [ ] **Step 3: Implement atomic-enough metadata read/write helpers** using `ConvertFrom-Json`/`ConvertTo-Json`, create the ProgramData directory only when saving, and surface save errors.
- [ ] **Step 4: Update share scanning** to merge live SMB shares with metadata records and mark missing live mappings as `Paused` without deleting the record.
- [ ] **Step 5: Run the test and verify it passes; parse the PowerShell source.

### Task 2: Create, pause, resume, and delete behavior

**Files:**
- Modify: `源码/主程序-3.0.ps1:263-354,1089-1155`
- Modify: `ui-layout.test.ps1`

**Interfaces:**
- `Set-ManagedShare` writes/updates metadata after successful SMB/NTFS setup.
- Add `Pause-ManagedShare`, `Resume-ManagedShare`, and `Delete-ManagedShareRecord`.
- Keep `Remove-Share` for external-share close behavior only.

- [ ] **Step 1: Write failing assertions** for pause retaining metadata, resume calling the existing creation path, delete removing only metadata plus mapping, and folder-preservation messages.
- [ ] **Step 2: Run the test and verify the behavior assertions fail before implementation.
- [ ] **Step 3: Implement pause/resume/delete with rollback-safe ordering:** save metadata after successful create/update, remove only the SMB mapping on pause, recreate the mapping from metadata on resume, and remove metadata only after a confirmed delete action.
- [ ] **Step 4: Run static tests and PowerShell parsing again.

### Task 3: WPF actions and status presentation

**Files:**
- Modify: `源码/主程序-3.0.ps1:776-910,1089-1155`
- Modify: `ui-layout.test.ps1`

**Interfaces:**
- `Add-ShareCard` consumes `Paused` and renders the correct action set.
- Confirmation dialogs use existing `Show-AppDialog` and `Show-Error`.

- [ ] **Step 1: Write failing assertions** for “暂停共享”, “重新开启”, “删除记录”, and “已暂停” labels, while asserting search/refresh remain absent.
- [ ] **Step 2: Run the test and verify it fails against the current UI.
- [ ] **Step 3: Add paused-state card styling and wire each action to the new behavior functions; keep external-share buttons unchanged.
- [ ] **Step 4: Run the test, parser, and `git diff --check`.

### Task 4: Build and runtime verification

**Files:**
- Modify: `开发进度.md` and `README.md` only if the final behavior is confirmed.
- Create: next version under `打包输出/` via `build.ps1`.

- [ ] **Step 1: Build with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1` and verify a new EXE is created without overwriting older versions.
- [ ] **Step 2: Launch the new EXE and verify the list, paused state, resume state, and delete confirmation without deleting a real user folder.
- [ ] **Step 3: Verify the metadata file contains no password and that deleting a record leaves the target folder intact.
- [ ] **Step 4: Update progress documentation with the confirmed version and remaining real-device SMB limitations.
