Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 helpers for focusing Teams
$signature = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win32 {
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
[DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
[DllImport("user32.dll")]
public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
"@
Add-Type $signature

# ---------- UI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "F15 Mischief Manager ~(=^.^)~"
$form.Size = New-Object System.Drawing.Size(580, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 240, 255)

# ASCII mascot + banner (pure ASCII - no Unicode box chars)
$ascii = @"
/\_/\  MEET F15 FELIX
( o.o )  Official Key Pusher
 > ^ <   (He naps between presses)

.~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~.
|  I will poke Teams politely w/ F15  |
*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*~*
Pro tip: Felix prefers snacks & praise.
"@

$lblArt = New-Object System.Windows.Forms.Label
$lblArt.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$lblArt.ForeColor = [System.Drawing.Color]::FromArgb(70, 50, 120)
$lblArt.AutoSize = $false
$lblArt.Size = New-Object System.Drawing.Size(545, 145)
$lblArt.Location = New-Object System.Drawing.Point(12, 8)
$lblArt.Text = $ascii
$form.Controls.Add($lblArt)

# Separator line
$sep = New-Object System.Windows.Forms.Label
$sep.Text = ""
$sep.BorderStyle = 'Fixed3D'
$sep.Size = New-Object System.Drawing.Size(545, 2)
$sep.Location = New-Object System.Drawing.Point(12, 158)
$form.Controls.Add($sep)

# Normal interval controls
$lblNormal = New-Object System.Windows.Forms.Label
$lblNormal.Text = "Normal interval (seconds):"
$lblNormal.Location = New-Object System.Drawing.Point(12, 172)
$lblNormal.Size = New-Object System.Drawing.Size(200, 20)
$lblNormal.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($lblNormal)

$numNormal = New-Object System.Windows.Forms.NumericUpDown
$numNormal.Minimum = 1
$numNormal.Maximum = 86400
$numNormal.Value = 60
$numNormal.Location = New-Object System.Drawing.Point(215, 170)
$numNormal.Size = New-Object System.Drawing.Size(90, 22)
$form.Controls.Add($numNormal)

# Random interval controls
$lblRand = New-Object System.Windows.Forms.Label
$lblRand.Text = "Random interval (min - max seconds):"
$lblRand.Location = New-Object System.Drawing.Point(12, 204)
$lblRand.Size = New-Object System.Drawing.Size(280, 20)
$lblRand.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($lblRand)

$numRandMin = New-Object System.Windows.Forms.NumericUpDown
$numRandMin.Minimum = 1
$numRandMin.Maximum = 86400
$numRandMin.Value = 10
$numRandMin.Location = New-Object System.Drawing.Point(12, 228)
$numRandMin.Size = New-Object System.Drawing.Size(90, 22)
$form.Controls.Add($numRandMin)

$lblTo = New-Object System.Windows.Forms.Label
$lblTo.Text = "to"
$lblTo.Location = New-Object System.Drawing.Point(108, 231)
$lblTo.Size = New-Object System.Drawing.Size(20, 18)
$lblTo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($lblTo)

$numRandMax = New-Object System.Windows.Forms.NumericUpDown
$numRandMax.Minimum = 1
$numRandMax.Maximum = 86400
$numRandMax.Value = 120
$numRandMax.Location = New-Object System.Drawing.Point(130, 228)
$numRandMax.Size = New-Object System.Drawing.Size(90, 22)
$form.Controls.Add($numRandMax)

# --- Helper function for styled buttons ---
function New-StyledButton {
    param($text, $x, $y, $w, $h, $bgColor, $fgColor)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Size = New-Object System.Drawing.Size($w, $h)
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = $bgColor
    $btn.ForeColor = $fgColor
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 160, 220)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

# Action buttons row 1
$btnNormal = New-StyledButton "(=^.^=) Gentle Boop Mode" 12 270 262 38 `
    ([System.Drawing.Color]::FromArgb(180, 230, 200)) `
    ([System.Drawing.Color]::FromArgb(30, 80, 50))

$btnRandom = New-StyledButton "(>^.^<) Surprise! Mode" 282 270 262 38 `
    ([System.Drawing.Color]::FromArgb(200, 210, 255)) `
    ([System.Drawing.Color]::FromArgb(40, 30, 100))

$form.Controls.Add($btnNormal)
$form.Controls.Add($btnRandom)

# Action buttons row 2
$btnStop = New-StyledButton "Halt Felix (Stop)" 12 318 140 34 `
    ([System.Drawing.Color]::FromArgb(255, 200, 200)) `
    ([System.Drawing.Color]::FromArgb(120, 20, 20))
$btnStop.Enabled = $false

$btnPokeOnce = New-StyledButton "Poke Teams Once" 158 318 150 34 `
    ([System.Drawing.Color]::FromArgb(255, 235, 180)) `
    ([System.Drawing.Color]::FromArgb(100, 60, 0))

$btnExit = New-StyledButton "Close & Feed Felix >^.^<" 314 318 230 34 `
    ([System.Drawing.Color]::FromArgb(230, 200, 255)) `
    ([System.Drawing.Color]::FromArgb(70, 20, 120))

$form.Controls.Add($btnStop)
$form.Controls.Add($btnPokeOnce)
$form.Controls.Add($btnExit)

# Status bar panel
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(12, 364)
$statusPanel.Size = New-Object System.Drawing.Size(545, 70)
$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(235, 225, 255)
$statusPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($statusPanel)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Mode: Idle | Felix is curled up and dreaming of F-keys..."
$lblStatus.Location = New-Object System.Drawing.Point(8, 8)
$lblStatus.Size = New-Object System.Drawing.Size(528, 55)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(60, 40, 100)
$statusPanel.Controls.Add($lblStatus)

# ---------- Logic ----------
$winFormsTimer = $null
$threadTimer = $null
$mode = "Idle"
$rand = New-Object System.Random

$quips = @(
    "Felix hums a tiny victory tune. ~(=^w^)~",
    "Felix demands a treat after every 10 pokes. (=*^.^*=)",
    "Felix is on coffee break. He still pokes though. (=^-^=)",
    "Felix wonders if F15 is a secret handshake. (=^?^=)",
    "Felix practices his dramatic eyebrow raise. (=^o^=)",
    "Felix reports mission accomplished. Good boy. (=^v^=)",
    "Felix is judging your screen time. (=^.___.^=)",
    "Felix says: another successful nudge! (=^._.^=)",
    "Felix logged the poke. Very professional. (=^-.^=)",
    "Felix stretches triumphantly. /\_/\ zoomies!"
)

# ---------- Teams focus helpers ----------
function Get-TeamsWindowHandle {
    $proc = Get-Process -Name Teams -ErrorAction SilentlyContinue
    if (-not $proc) { return [IntPtr]::Zero }
    if ($proc.MainWindowHandle -ne 0) { return [IntPtr]$proc.MainWindowHandle }
    $script:found = [IntPtr]::Zero
    $callback = [Win32+EnumWindowsProc]{
        param($hWnd, $lParam)
        $pid = 0
        [Win32]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null
        if ($pid -eq $lParam.ToInt32()) {
            if ([Win32]::IsWindowVisible($hWnd)) {
                $sb = New-Object System.Text.StringBuilder 256
                [Win32]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
                $title = $sb.ToString()
                if ($title -and $title -match "Teams") {
                    $script:found = $hWnd; return $false
                }
                $script:found = $hWnd; return $false
            }
        }
        return $true
    }
    [Win32]::EnumWindows($callback, [IntPtr]$proc.Id) | Out-Null
    return $script:found
}

function Focus-Teams {
    param($updateStatus = $true)
    $hWnd = Get-TeamsWindowHandle
    if ($hWnd -eq [IntPtr]::Zero) {
        if ($updateStatus) {
            $form.Invoke([action]{ $lblStatus.Text = "Teams not found. (=^o.o^=)? Felix is confused." })
        }
        return $false
    }
    try {
        [Win32]::ShowWindowAsync($hWnd, 9) | Out-Null
        Start-Sleep -Milliseconds 150
        [Win32]::SetForegroundWindow($hWnd) | Out-Null
        Start-Sleep -Milliseconds 100
        return $true
    } catch {
        if ($updateStatus) {
            $form.Invoke([action]{ $lblStatus.Text = "Failed to focus Teams: $($_.Exception.Message)" })
        }
        return $false
    }
}

function Send-F15 {
    param($reason)
    try {
        $focused = Focus-Teams $true
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if (-not $focused) {
            $form.Invoke([action]{ $lblStatus.Text = "Mode: $mode | Last attempt: $time | Teams not found. Felix sighs." })
            Write-Host "Attempted F15 at $time but Teams not found ($reason)"
            return
        }
        [System.Windows.Forms.SendKeys]::SendWait("{F15}")
        $quip = if ($rand.Next(1,4) -eq 2) { $quips[$rand.Next(0, $quips.Count)] } else { "Felix reports success! (=^v^=)" }
        $form.Invoke([action]{ $lblStatus.Text = "Mode: $mode | Last sent: $time | $quip" })
        Write-Host "Sent F15 at $time ($reason) - $quip"
    } catch {
        $form.Invoke([action]{ $lblStatus.Text = "Uh oh! Error: $($_.Exception.Message) Felix is embarrassed." })
        Write-Host "Error sending F15: $($_.Exception.Message)"
    }
}

function Stop-AllTimers {
    if ($winFormsTimer -ne $null) {
        $winFormsTimer.Stop(); $winFormsTimer.Dispose(); $script:winFormsTimer = $null
    }
    if ($threadTimer -ne $null) {
        try { $threadTimer.Change([System.Threading.Timeout]::Infinite, [System.Threading.Timeout]::Infinite) } catch {}
        try { $threadTimer.Dispose() } catch {}
        $script:threadTimer = $null
    }
    $script:mode = "Idle"
    $form.Invoke([action]{
        $btnStop.Enabled = $false
        $btnNormal.Enabled = $true
        $btnRandom.Enabled = $true
        $lblStatus.Text = "Mode: Idle | Felix has clocked out and returned to napping. /\_/\"
    })
}

# Normal mode
$btnNormal.Add_Click({
    Stop-AllTimers
    $intervalSec = [int]$numNormal.Value
    $script:mode = "Normal (Gentle Boop)"
    $form.Invoke([action]{ $btnStop.Enabled = $true; $btnNormal.Enabled = $false; $btnRandom.Enabled = $false })
    $script:winFormsTimer = New-Object System.Windows.Forms.Timer
    $script:winFormsTimer.Interval = $intervalSec * 1000
    $script:winFormsTimer.Add_Tick({ Send-F15 "Normal interval ${intervalSec}s" })
    Send-F15 "Normal start (immediate)"
    $script:winFormsTimer.Start()
    $form.Invoke([action]{ $lblStatus.Text = "Mode: Normal | Every ${intervalSec}s | Felix is on duty and very serious. (=^-.^=)" })
})

# Random mode
$btnRandom.Add_Click({
    Stop-AllTimers
    $minSec = [int]$numRandMin.Value
    $maxSec = [int]$numRandMax.Value
    if ($minSec -gt $maxSec) { $tmp = $minSec; $minSec = $maxSec; $maxSec = $tmp }
    $script:mode = "Random (Surprise!)"
    $form.Invoke([action]{ $btnStop.Enabled = $true; $btnNormal.Enabled = $false; $btnRandom.Enabled = $false })
    $form.Invoke([action]{ $lblStatus.Text = "Mode: Random | Felix is plotting surprises... (>^.^<)" })

    $callback = [System.Threading.TimerCallback]{
        param($state)
        $form.Invoke([action]{ Send-F15 "Random mode" })
        $next = $rand.Next($minSec, $maxSec + 1)
        try {
            $threadTimer.Change($next * 1000, [System.Threading.Timeout]::Infinite) | Out-Null
            $form.Invoke([action]{ $lblStatus.Text = "Mode: Random | Next poke in ${next}s | Felix giggles quietly." })
        } catch {}
    }

    $script:threadTimer = New-Object System.Threading.Timer($callback, $null, [System.Threading.Timeout]::Infinite, [System.Threading.Timeout]::Infinite)
    Send-F15 "Random start (immediate)"
    $nextInitial = $rand.Next($minSec, $maxSec + 1)
    $script:threadTimer.Change($nextInitial * 1000, [System.Threading.Timeout]::Infinite) | Out-Null
    $form.Invoke([action]{ $lblStatus.Text = "Mode: Random | First poke in ${nextInitial}s | Felix hides a squeaky toy." })
})

# Single poke
$btnPokeOnce.Add_Click({ Send-F15 "Manual poke" })

# Stop
$btnStop.Add_Click({ Stop-AllTimers })

# Exit
$btnExit.Add_Click({ Stop-AllTimers; $form.Close() })

# Cleanup on close
$form.Add_FormClosing({ Stop-AllTimers })

[void]$form.ShowDialog()
