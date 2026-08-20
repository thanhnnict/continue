# Issue: Continue Extension Không Capture Output Khi Chạy Command Trên Remote SSH

## 📋 Summary

**Issue**: Continue extension's built-in `runTerminalCommand` tool không thể capture output khi làm việc trên Remote SSH environment.

**Status**: ✅ **Solved** (2025-08-20)

**Solution**: Tạo MCP server `remote-ssh-terminal` chạy trên local Mac, dùng SSH để execute commands trên remote và capture stdout/stderr.

---

## 🎯 Problem Statement

### Hiện tượng

Khi user làm việc trên Remote SSH workspace và yêu cầu model chạy command:

```
User: "Run `ls -la /home/devops` and show me the output"

Model: "Command executed in remote terminal. Output capture is not yet available for remote environments."
```

**Vấn đề**: 
- ✅ Command được execute trên remote
- ❌ Output KHÔNG được capture và trả về cho model
- ❌ Model không thể đọc kết quả để tiếp tục conversation

### Impact

- Model không thể debug remote server
- Model không thể verify kết quả sau khi chạy command
- User phải manually copy-paste output từ terminal vào chat
- Giảm hiệu suất làm việc trên remote environment

---

## 🔍 Root Cause Analysis

### 1. VS Code API Limitation

Continue extension sử dụng VS Code API `terminal.sendText()` để chạy command trên remote:

```typescript
// extensions/vscode/src/VsCodeIde.ts
async runCommand(command: string): Promise<void> {
  const terminal = this.getOrCreateTerminal();
  terminal.sendText(command, false); // ❌ Không capture output
}
```

**Vấn đề**: 
- `terminal.sendText()` chỉ gửi command đến terminal
- VS Code API **không có method** để capture output từ terminal
- Output được hiển thị trong VS Code terminal UI, nhưng không accessible qua API

### 2. Extension Host Architecture

Khi làm việc trên Remote SSH:

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Mac (goku-)                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              VS Code IDE                             │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  Extension Host (Local)                     │   │   │
│  │  │  - Continue Extension                       │   │   │
│  │  │  - runTerminalCommand tool                  │   │   │
│  │  │  - MCP Client                               │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ SSH
┌─────────────────────────────────────────────────────────────┐
│                    Remote Server (devops@devops-gpu-vt-tpb)  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              VS Code Server                          │   │
│  │  - Terminal (display output)                        │   │
│  │  - Filesystem                                       │   │
│  │  - Shell processes                                  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Vấn đề**: 
- Extension host chạy trên **local Mac**
- Terminal chạy trên **remote server**
- Không có cách để extension host capture output từ remote terminal

### 3. Why Built-in Tool Fails

```typescript
// core/tools/implementations/runTerminalCommand.ts
export class RunTerminalCommandTool implements Tool {
  async execute(command: string): Promise<ToolResult> {
    if (this.isRemote()) {
      // ❌ Remote: chỉ send command, không capture output
      await this.ide.runCommand(command);
      return {
        success: true,
        output: "Command executed in remote terminal. Output capture is not yet available for remote environments."
      };
    } else {
      // ✅ Local: dùng child_process, capture output
      return this.executeLocal(command);
    }
  }
}
```

---

## 💡 Solution: MCP Remote SSH Terminal Server

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Mac (goku-)                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              VS Code IDE                             │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  Extension Host (Local)                     │   │   │
│  │  │  ┌─────────────────────────────────────┐    │   │   │
│  │  │  │  MCP Client                          │    │   │   │
│  │  │  │  (StdioClientTransport)              │    │   │   │
│  │  │  └──────────────┬──────────────────────┘    │   │   │
│  │  │                 │                            │   │   │
│  │  │                 ▼                            │   │   │
│  │  │  ┌─────────────────────────────────────┐    │   │   │
│  │  │  │  MCP Server (stdio)                 │    │   │   │
│  │  │  │  (server.js)                        │    │   │   │
│  │  │  └──────────────┬──────────────────────┘    │   │   │
│  │  │                 │                            │   │   │
│  │  │                 ▼                            │   │   │
│  │  │  ┌─────────────────────────────────────┐    │   │   │
│  │  │  │  child_process.spawn()              │    │   │   │
│  │  │  │  (ssh command)                      │    │   │   │
│  │  │  └─────────────────────────────────────┘    │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ SSH
┌─────────────────────────────────────────────────────────────┐
│                    Remote Server (devops@devops-gpu-vt-tpb)  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SSH Server                              │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │  Shell Process (bash -c "command")          │   │   │
│  │  │  - stdout ──────────────────────────────────┼───┼───▶
│  │  │  - stderr ──────────────────────────────────┼───┼───▶
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### How It Works

1. **User** yêu cầu model chạy command trên remote
2. **Model** gọi tool `run_command` từ MCP server
3. **MCP Server** (chạy trên local Mac) nhận command
4. **MCP Server** execute `ssh devops@devops-gpu-vt-tpb "command"`
5. **SSH** connect đến remote server và chạy command
6. **Remote shell** execute command và output stdout/stderr
7. **SSH** capture output và trả về local
8. **MCP Server** parse output và trả về cho model
9. **Model** đọc output và tiếp tục conversation

### Key Features

| Feature | Description |
|---------|-------------|
| **Capture stdout** | ✅ Capture toàn bộ output từ remote |
| **Capture stderr** | ✅ Capture error messages |
| **Exit code** | ✅ Trả về exit code của command |
| **Timeout** | ✅ Default 2 phút, có thể customize |
| **CWD support** | ✅ Chạy command trong directory cụ thể |
| **Output truncation** | ✅ Truncate output > 100KB để tránh context overflow |
| **Color disable** | ✅ Disable ANSI colors cho output cleaner |

---

## 📁 Implementation

### File Structure

```
~/.tiep-tuc/mcp-remote-ssh/
├── server.js       # MCP server (main file)
├── test.js         # Test script
├── package.json    # Dependencies
└── README.md       # Documentation
```

### Key Code: `server.js`

```javascript
const { spawn } = require("node:child_process");

// Remote SSH configuration
const REMOTE_HOST = process.env.REMOTE_SSH_HOST || "devops@devops-gpu-vt-tpb";
const REMOTE_SSH_OPTIONS = [
  "-o", "ConnectTimeout=10",
  "-o", "StrictHostKeyChecking=no",
  "-o", "BatchMode=yes",
];

function executeRemoteCommand(command, cwd, timeoutMs) {
  return new Promise((resolve) => {
    // Build SSH command
    const sshCommand = cwd 
      ? `cd '${cwd}' && ${command}`
      : command;
    
    const sshArgs = [
      ...REMOTE_SSH_OPTIONS,
      REMOTE_HOST,
      sshCommand,
    ];

    const child = spawn("ssh", sshArgs, {
      cwd: os.homedir(),
      env: {
        ...process.env,
        FORCE_COLOR: "0",
        NO_COLOR: "1",
      },
    });

    let stdout = "";
    let stderr = "";
    
    child.stdout?.on("data", (data) => {
      stdout += data.toString();
    });

    child.stderr?.on("data", (data) => {
      stderr += data.toString();
    });

    child.on("close", (code, signal) => {
      resolve({
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        exitCode: code,
        signal: signal || undefined,
        remoteHost: REMOTE_HOST,
      });
    });
  });
}
```

### MCP Tool Definition

```javascript
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "run_command",
      description:
        "Execute a shell command on the remote SSH server and capture stdout/stderr. " +
        `Remote host: ${REMOTE_HOST}`,
      inputSchema: {
        type: "object",
        properties: {
          command: {
            type: "string",
            description: "The shell command to execute on the remote server",
          },
          cwd: {
            type: "string",
            description: "Working directory on the remote server (optional)",
          },
          timeout: {
            type: "number",
            description: "Timeout in milliseconds (optional, defaults to 120000)",
          },
        },
        required: ["command"],
      },
    },
  ],
}));
```

---

## ⚙️ Configuration

### `~/.tiep-tuc/config.yaml`

```yaml
mcpServers:
  # Remote SSH Terminal — capture output khi làm việc trên Remote SSH
  # Built-in runTerminalCommand KHÔNG capture được output trên remote
  # MCP server chạy trên local Mac (extension host), dùng SSH để chạy command trên remote
  # Capture stdout/stderr từ remote server
  - name: remote-ssh-terminal
    command: /Users/goku-/miniconda3/envs/node20/bin/node
    args:
      - /Users/goku-/.tiep-tuc/mcp-remote-ssh/server.js
    env:
      REMOTE_SSH_HOST: devops@devops-gpu-vt-tpb
```

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `REMOTE_SSH_HOST` | ✅ | SSH host (user@hostname) | `devops@devops-gpu-vt-tpb` |

### Requirements

- **SSH key** phải đã được setup (không cần password)
- **Remote server** phải accessible từ local Mac
- **Node.js** v20+ phải được install trên local Mac

---

## 🧪 Testing

### Test Script

```bash
cd ~/.tiep-tuc/mcp-remote-ssh
node test.js
```

### Test Results (2025-08-20)

```
=== MCP Remote SSH Terminal Server Test ===

[1] Testing initialize...
    Server: remote-ssh-terminal
    Protocol: 2024-11-05
[1] Initialize: OK

[2] Testing tools/list...
    Tools: ["run_command"]
[2] List tools: OK

[3] Testing run_command with 'echo'...
    Output: Hello from remote SSH!
[3] Run 'echo': OK

[4] Testing run_command with 'whoami && hostname'...
    Output: devops | 09a3335f-f01e-438a-be47-64b3d4d3fa3f | /home/devops
[4] Run 'whoami': OK

[5] Testing error case (ls /nonexistent)...
    Error captured: OK
[5] Error case: OK

[6] Testing run_command with cwd=/tmp...
    CWD: /tmp (correct)
[6] CWD test: OK

=== All tests completed! ===
```

**Result**: ✅ 6/6 tests passed

---

## 📊 Comparison: Built-in Tool vs MCP Server

| Feature | Built-in `runTerminalCommand` | MCP `remote-ssh-terminal` |
|---------|-------------------------------|---------------------------|
| Chạy trên remote | ✅ | ✅ |
| Capture stdout | ❌ | ✅ |
| Capture stderr | ❌ | ✅ |
| Exit code | ❌ | ✅ |
| Timeout | ✅ | ✅ |
| CWD support | ❌ | ✅ |
| Output truncation | ❌ | ✅ (100KB) |
| Color disable | ❌ | ✅ |

---

## 🐛 Known Issues & Limitations

### 1. SSH Connection Overhead

**Issue**: Mỗi lần chạy command phải establish SSH connection mới.

**Impact**: 
- Slow hơn so với local execution
- Có thể timeout nếu remote server slow

**Workaround**: 
- Tăng timeout: `{"command": "...", "timeout": 300000}`
- Dùng SSH multiplexing (tương lai)

### 2. No Interactive Commands

**Issue**: Không thể chạy interactive commands (ví dụ: `vim`, `top`, `htop`).

**Reason**: SSH không support interactive TTY qua MCP protocol.

**Workaround**: 
- Dùng non-interactive commands
- Chạy interactive commands manually trong VS Code terminal

### 3. Output Size Limit

**Issue**: Output > 100KB sẽ bị truncate.

**Reason**: Tránh context overflow cho LLM.

**Workaround**: 
- Dùng `head`, `tail`, `grep` để filter output
- Chạy command multiple lần với different parameters

### 4. Single Remote Host

**Issue**: Chỉ support một remote host per MCP server instance.

**Reason**: Config đơn giản, dễ quản lý.

**Workaround**: 
- Tạo multiple MCP server instances với different `REMOTE_SSH_HOST`
- Ví dụ:
  ```yaml
  mcpServers:
    - name: remote-ssh-tpb
      env:
        REMOTE_SSH_HOST: devops@devops-gpu-vt-tpb
    - name: remote-ssh-other
      env:
        REMOTE_SSH_HOST: devops@devops-gpu-vt-other
  ```

---

## 🔧 Troubleshooting

### "ssh: Could not resolve hostname"

**Cause**: `REMOTE_SSH_HOST` sai hoặc remote server không accessible.

**Fix**:
```bash
# Kiểm tra hostname
ping devops-gpu-vt-tpb

# Kiểm tra SSH connection
ssh devops@devops-gpu-vt-tpb "echo 'SSH OK'"
```

### "Permission denied (publickey)"

**Cause**: SSH key chưa được setup.

**Fix**:
```bash
# Copy SSH public key đến remote
ssh-copy-id devops@devops-gpu-vt-tpb

# Verify
ssh devops@devops-gpu-vt-tpb "whoami"
```

### "Command timed out"

**Cause**: Command chạy quá 2 phút (default timeout).

**Fix**:
```json
{
  "command": "long_running_command",
  "timeout": 300000
}
```

### "Output is empty"

**Cause**: Command không có output, hoặc output bị redirect.

**Fix**:
```bash
# Kiểm tra command có output không
ssh devops@devops-gpu-vt-tpb "command"

# Nếu output bị redirect, dùng 2>&1
ssh devops@devops-gpu-vt-tpb "command 2>&1"
```

---

## 📝 Usage Examples

### Basic Command

```json
{
  "command": "ls -la /home/devops"
}
```

**Output**:
```
[Remote: devops@devops-gpu-vt-tpb]
[CWD: (home directory)]

total 42
drwxr-xr-x  5 devops devops 4096 Aug 15 10:30 .
drwxr-xr-x 12 devops devops 4096 Aug 10 08:00 ..
drwxr-xr-x  8 devops devops 4096 Aug 14 16:22 my-project
...

[exit code: 0]
```

### With CWD

```json
{
  "command": "ls -la",
  "cwd": "/home/devops/projects"
}
```

### With Timeout

```json
{
  "command": "sleep 10 && echo 'Done'",
  "timeout": 30000
}
```

### Capture Errors

```json
{
  "command": "ls /nonexistent/path"
}
```

**Output**:
```
[Remote: devops@devops-gpu-vt-tpb]
[CWD: (home directory)]

[stderr]
ls: cannot access '/nonexistent/path': No such file or directory

[exit code: 2]
```

### System Information

```json
{
  "command": "uname -a && hostname && whoami && pwd"
}
```

**Output**:
```
[Remote: devops@devops-gpu-vt-tpb]
[CWD: (home directory)]

Linux 09a3335f-f01e-438a-be47-64b3d4d3fa3f 5.15.0-105-generic #115-Ubuntu SMP Mon Apr 15 09:50:01 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux
09a3335f-f01e-438a-be47-64b3d4d3fa3f
devops
/home/devops

[exit code: 0]
```

---

## 🔄 Future Enhancements

### 1. SSH Multiplexing

**Goal**: Reuse SSH connection để giảm overhead.

**Implementation**:
```bash
# SSH config (~/.ssh/config)
Host devops-gpu-vt-tpb
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
```

### 2. Multiple Remote Hosts

**Goal**: Support multiple remote servers trong một MCP server.

**Implementation**:
```javascript
// Dynamic host selection
const { command, host, cwd, timeout } = request.params.arguments;
const targetHost = host || REMOTE_HOST;
```

### 3. File Transfer

**Goal**: Upload/download files qua MCP.

**Implementation**:
```javascript
// New tools: upload_file, download_file
// Use scp or sftp
```

### 4. Real-time Output Streaming

**Goal**: Stream output real-time cho long-running commands.

**Implementation**:
```javascript
// Use MCP streaming protocol
// Send partial output as it arrives
```

### 5. Command History & Session

**Goal**: Track command history, maintain session state.

**Implementation**:
```javascript
// Store command history in memory
// Support session-based commands
```

---

## 📚 References

- [Continue Extension Documentation](https://docs.continue.dev/)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
- [SSH Multiplexing Guide](https://www.ssh.com/ssh/multiplexing)

---

## 📅 Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2025-08-20 | 1.0.0 | Initial release - MCP Remote SSH Terminal Server |

---

## ✅ Current Status (2025-08-20)

### Completed

- ✅ Root cause analysis
- ✅ Solution design
- ✅ MCP server implementation
- ✅ Testing (6/6 tests passed)
- ✅ Configuration
- ✅ Documentation

### Active

- ✅ MCP server deployed trên local Mac
- ✅ Config.yaml updated
- ✅ Ready to use

### Next Steps

1. **User**: Reload VS Code window
2. **User**: Test MCP server trên remote SSH workspace
3. **Monitor**: Gather feedback từ actual usage
4. **Enhance**: Implement future enhancements based on feedback

---

## 📞 Contact

**Issue reported by**: goku-  
**Resolved by**: goku- + AI assistant  
**Date resolved**: 2025-08-20
