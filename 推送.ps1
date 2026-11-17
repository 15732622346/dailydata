# 推送.ps1 —— 按 协作说明.md 的顺序逐级尝试推送，并核对本地与远程哈希
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\推送.ps1
#   powershell -ExecutionPolicy Bypass -File .\推送.ps1 -Message "提交说明"   # 先 add+commit 再推送

param(
    [string]$Message = "",
    [string]$Branch = "master",
    [string]$Remote = "origin"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

function Clear-ProxyEnv {
    foreach ($n in @("ALL_PROXY","all_proxy","HTTP_PROXY","http_proxy","HTTPS_PROXY","https_proxy")) {
        Set-Item -Path "Env:$n" -Value $null -ErrorAction SilentlyContinue
    }
}

# 直接用进程对象取 stdout/stderr，避免 PowerShell 把 git 的 stderr 当成异常抛到屏幕上
function Invoke-Git {
    param([string[]]$GitArgs)
    $quoted = $GitArgs | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = ($quoted -join " ")
    $psi.WorkingDirectory = (Get-Location).Path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Output = ($stdout + $stderr).Trim() }
}

if ($Message -ne "") {
    $r = Invoke-Git @("add","-A")
    if ($r.Code -ne 0) { Write-Host "git add 失败：$($r.Output)"; exit 1 }
    $r = Invoke-Git @("commit","-m",$Message)
    Write-Host $r.Output
    if ($r.Code -ne 0 -and $r.Output -notmatch "nothing to commit") { exit 1 }
}

Clear-ProxyEnv

$attempts = @(
    @{ Name = "直连（清空代理）";         Args = @("-c","http.proxy=","-c","https.proxy=") },
    @{ Name = "本地代理 127.0.0.1:7892"; Args = @("-c","http.proxy=http://127.0.0.1:7892","-c","https.proxy=http://127.0.0.1:7892") },
    @{ Name = "直连 + TLS1.2 + HTTP/1.1"; Args = @("-c","http.proxy=","-c","https.proxy=","-c","http.sslVersion=tlsv1.2","-c","http.version=HTTP/1.1") }
)

$pushed = $false
foreach ($a in $attempts) {
    Write-Host "尝试：$($a.Name)"
    $r = Invoke-Git ($a.Args + @("push", $Remote, $Branch))
    if ($r.Code -eq 0) {
        Write-Host "  成功：$($r.Output)"
        $pushed = $true
        break
    }
    $brief = ($r.Output -split "`n" | Where-Object { $_ -match "fatal|error" } | Select-Object -First 2) -join " | "
    Write-Host "  失败：$brief"
}

if (-not $pushed) {
    Write-Host "三种方式都失败，按 协作说明.md 继续排查 DNS、443 端口与凭据。"
    exit 1
}

$local = (Invoke-Git @("rev-parse","HEAD")).Output
$remoteOut = (Invoke-Git @("-c","http.proxy=","-c","https.proxy=","ls-remote", $Remote, "refs/heads/$Branch")).Output
$remoteHash = ($remoteOut -split "`t")[0]
Write-Host "LOCAL =$local"
Write-Host "REMOTE=$remoteHash"
if ($local -eq $remoteHash) {
    Write-Host "推送完成，本地与远程一致。"
    exit 0
}
Write-Host "本地与远程不一致，请重新执行。"
exit 1
