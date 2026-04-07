Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide the PowerShell console window
Add-Type -Name ConsoleUtils -Namespace Win32 -MemberDefinition '
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'
[Win32.ConsoleUtils]::ShowWindow([Win32.ConsoleUtils]::GetConsoleWindow(), 0) | Out-Null

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

# ---------- Colors (EP-133 olive palette) ----------
$clrFormBg     = [System.Drawing.Color]::FromArgb(22,  27,  16)   # dark army olive
$clrHeaderBg   = [System.Drawing.Color]::FromArgb(13,  16,   9)   # near-black olive
$clrHeaderText = [System.Drawing.Color]::FromArgb(220, 210, 165)  # warm cream
$clrHeaderSub  = [System.Drawing.Color]::FromArgb(120, 138,  80)  # muted olive gold
$clrLCDBezel   = [System.Drawing.Color]::FromArgb(16,  20,  12)   # dark olive bezel
$clrLCDBg      = [System.Drawing.Color]::FromArgb(10,  22,  14)   # phosphor screen
$clrLCDText    = [System.Drawing.Color]::FromArgb(168, 214,  90)  # bright phosphor green
$clrLCDAmber   = [System.Drawing.Color]::FromArgb(210, 160,  45)  # amber status
$clrOrange     = [System.Drawing.Color]::FromArgb(228,  92,  28)  # TE signature orange
$clrInputBg    = [System.Drawing.Color]::FromArgb(16,  20,  12)
$clrInputLabel = [System.Drawing.Color]::FromArgb(120, 138,  80)
$clrLogBg      = [System.Drawing.Color]::FromArgb(6,   12,   8)

# ---------- Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "FELIX"
$form.Size            = New-Object System.Drawing.Size(580, 740)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.BackColor       = $clrFormBg

# ---------- Helper: Double-buffer via reflection ----------
function Enable-DoubleBuffer {
    param($control)
    $prop = $control.GetType().GetProperty(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]'NonPublic,Instance'
    )
    $prop.SetValue($control, $true, $null)
}

# ---------- Helper: LED dot ----------
function New-LEDPanel {
    param([int]$X, [int]$Y, [System.Drawing.Color]$Color)
    $led           = New-Object System.Windows.Forms.Panel
    $led.Location  = New-Object System.Drawing.Point($X, $Y)
    $led.Size      = New-Object System.Drawing.Size(12, 12)
    $led.BackColor = [System.Drawing.Color]::Transparent
    $led.Tag       = $Color
    $led.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $b = New-Object System.Drawing.SolidBrush($sender.Tag)
        $g.FillEllipse($b, 1, 1, 10, 10)
        $b.Dispose()
        $rim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,0,0,0), 1)
        $g.DrawEllipse($rim, 1, 1, 10, 10)
        $rim.Dispose()
        $hi = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,255,255,255))
        $g.FillEllipse($hi, 3, 3, 3, 3)
        $hi.Dispose()
    })
    return $led
}

# ---------- Helper: Rounded pad button ----------
function New-PadButton {
    param(
        [string]$Text,
        [string]$SubText = "",
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [System.Drawing.Color]$ColorTop,
        [System.Drawing.Color]$ColorBottom,
        [System.Drawing.Color]$ColorText,
        [System.Drawing.Color]$ColorBorder,
        [int]$CornerRadius = 3
    )
    $btn              = New-Object System.Windows.Forms.Button
    $btn.Location     = New-Object System.Drawing.Point($X, $Y)
    $btn.Size         = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle    = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor    = [System.Drawing.Color]::Transparent
    $btn.Text         = ""
    $btn.Cursor       = [System.Windows.Forms.Cursors]::Hand
    $btn.Tag = @{
        MainText     = $Text
        SubText      = $SubText
        ColorTop     = $ColorTop
        ColorBottom  = $ColorBottom
        ColorText    = $ColorText
        ColorBorder  = $ColorBorder
        CornerRadius = $CornerRadius
        IsPressed    = $false
    }
    $btn.Add_MouseDown({ param($s,$e) $s.Tag.IsPressed = $true;  $s.Invalidate() })
    $btn.Add_MouseUp({ param($s,$e) $s.Tag.IsPressed = $false; $s.Invalidate() })
    $btn.Add_Paint({
        param($sender, $e)
        $g  = $e.Graphics
        $t  = $sender.Tag
        $r  = $t.CornerRadius
        $bw = $sender.Width
        $bh = $sender.Height
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $dim = if ($sender.Enabled) { 1.0 } else { 0.35 }
        $rawTop    = if ($t.IsPressed) { $t.ColorBottom } else { $t.ColorTop    }
        $rawBottom = if ($t.IsPressed) { $t.ColorTop    } else { $t.ColorBottom }
        $top    = [System.Drawing.Color]::FromArgb([int]($rawTop.R*$dim),   [int]($rawTop.G*$dim),    [int]($rawTop.B*$dim))
        $bottom = [System.Drawing.Color]::FromArgb([int]($rawBottom.R*$dim),[int]($rawBottom.G*$dim), [int]($rawBottom.B*$dim))
        $tc     = [System.Drawing.Color]::FromArgb([int]($t.ColorText.R*$dim),  [int]($t.ColorText.G*$dim),  [int]($t.ColorText.B*$dim))
        $bc     = [System.Drawing.Color]::FromArgb([int]($t.ColorBorder.R*$dim),[int]($t.ColorBorder.G*$dim),[int]($t.ColorBorder.B*$dim))
        $d    = $r * 2
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        if ($r -le 0) {
            $path.AddRectangle((New-Object System.Drawing.Rectangle(0, 0, $bw, $bh)))
        } else {
            $path.AddArc(0,       0,       $d, $d, 180, 90)
            $path.AddArc($bw-$d,  0,       $d, $d, 270, 90)
            $path.AddArc($bw-$d,  $bh-$d,  $d, $d,   0, 90)
            $path.AddArc(0,       $bh-$d,  $d, $d,  90, 90)
            $path.CloseFigure()
        }
        $g.SetClip($path)
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point(0,0)),
            (New-Object System.Drawing.Point(0,$bh)),
            $top, $bottom)
        $g.FillPath($grad, $path)
        $grad.Dispose()
        if ($sender.Enabled -and -not $t.IsPressed) {
            $hiPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(55,255,255,255), 1)
            $hiX = if ($r -le 0) { 1 } else { $r }
            $g.DrawLine($hiPen, $hiX, 2, ($bw - $hiX), 2)
            $hiPen.Dispose()
        }
        $g.ResetClip()
        $borderPen = New-Object System.Drawing.Pen($bc, 1.5)
        $g.DrawPath($borderPen, $path)
        $borderPen.Dispose()
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment     = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $tb = New-Object System.Drawing.SolidBrush($tc)
        # Pre-calculate geometry as explicit floats to avoid PowerShell
        # misreading ($bh/2)-2 as two separate constructor arguments
        $fw   = [float]($bw - 8)
        $fh   = [float]$bh
        $half = [float]($bh / 2)
        if ($t.SubText -ne "") {
            $mf       = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
            $subFont  = New-Object System.Drawing.Font("Consolas", 7)
            $rectTop  = New-Object System.Drawing.RectangleF([float]4, [float]6,  $fw, ($half - [float]2))
            $rectBot  = New-Object System.Drawing.RectangleF([float]4, ($half + [float]2), $fw, ($half - [float]8))
            $g.DrawString($t.MainText, $mf,      $tb, $rectTop, $sf)
            $g.DrawString($t.SubText,  $subFont, $tb, $rectBot, $sf)
            $mf.Dispose(); $subFont.Dispose()
        } else {
            $mf      = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
            $rectAll = New-Object System.Drawing.RectangleF([float]4, [float]0, $fw, $fh)
            $g.DrawString($t.MainText, $mf, $tb, $rectAll, $sf)
            $mf.Dispose()
        }
        $tb.Dispose(); $sf.Dispose(); $path.Dispose()
    })
    return $btn
}

# ---------- Helper: style and wrap NumericUpDown ----------
function Style-NUD {
    param($nud)
    $nud.BackColor   = [System.Drawing.Color]::FromArgb(10, 9, 7)
    $nud.ForeColor   = [System.Drawing.Color]::FromArgb(176, 210, 100)
    $nud.Font        = New-Object System.Drawing.Font("Consolas", 9)
    $nud.BorderStyle = 'FixedSingle'
}
function Wrap-NUD {
    param($nud, [int]$x, [int]$y)
    $wp           = New-Object System.Windows.Forms.Panel
    $wp.Location  = New-Object System.Drawing.Point($x, $y)
    $wp.Size      = New-Object System.Drawing.Size(($nud.Width+2), ($nud.Height+2))
    $wp.BackColor = [System.Drawing.Color]::FromArgb(100, 80, 30)
    $nud.Location = New-Object System.Drawing.Point(1, 1)
    $wp.Controls.Add($nud)
    return $wp
}

# ==================== UI BUILD ====================

# --- Header bar ---
$pnlHeader           = New-Object System.Windows.Forms.Panel
$pnlHeader.Location  = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size      = New-Object System.Drawing.Size(580, 56)
$pnlHeader.BackColor = $clrHeaderBg
Enable-DoubleBuffer $pnlHeader
$form.Controls.Add($pnlHeader)

$lblBrand           = New-Object System.Windows.Forms.Label
$lblBrand.Text      = "F E L I X"
$lblBrand.Font      = New-Object System.Drawing.Font("Consolas", 18, [System.Drawing.FontStyle]::Bold)
$lblBrand.ForeColor = $clrHeaderText
$lblBrand.BackColor = [System.Drawing.Color]::Transparent
$lblBrand.Location  = New-Object System.Drawing.Point(14, 8)
$lblBrand.Size      = New-Object System.Drawing.Size(400, 28)
$lblBrand.AutoSize  = $false
$pnlHeader.Controls.Add($lblBrand)

$lblSubBrand           = New-Object System.Windows.Forms.Label
$lblSubBrand.Text      = "K E Y   P U S H E R"
$lblSubBrand.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblSubBrand.ForeColor = $clrHeaderSub
$lblSubBrand.BackColor = [System.Drawing.Color]::Transparent
$lblSubBrand.Location  = New-Object System.Drawing.Point(14, 36)
$lblSubBrand.Size      = New-Object System.Drawing.Size(280, 16)
$pnlHeader.Controls.Add($lblSubBrand)

$script:led1 = New-LEDPanel -X 494 -Y 18 -Color ([System.Drawing.Color]::FromArgb(30,  60, 25))
$script:led2 = New-LEDPanel -X 514 -Y 18 -Color ([System.Drawing.Color]::FromArgb(60,  50, 15))
$script:led3 = New-LEDPanel -X 534 -Y 18 -Color ([System.Drawing.Color]::FromArgb(80,  34, 12))
$pnlHeader.Controls.Add($script:led1)
$pnlHeader.Controls.Add($script:led2)
$pnlHeader.Controls.Add($script:led3)

# --- LCD Bezel ---
$pnlLCDBezel           = New-Object System.Windows.Forms.Panel
$pnlLCDBezel.Location  = New-Object System.Drawing.Point(12, 62)
$pnlLCDBezel.Size      = New-Object System.Drawing.Size(556, 140)
$pnlLCDBezel.BackColor = $clrLCDBezel
Enable-DoubleBuffer $pnlLCDBezel
$pnlLCDBezel.Add_Paint({
    param($sender, $e)
    $g  = $e.Graphics
    $bw = $sender.Width; $bh = $sender.Height
    $dp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(8,8,6), 2)
    $lp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,50,38), 1)
    $g.DrawRectangle($dp, 1, 1, $bw-3, $bh-3)
    $g.DrawRectangle($lp, 3, 3, $bw-7, $bh-7)
    $dp.Dispose(); $lp.Dispose()
})
$form.Controls.Add($pnlLCDBezel)

# --- LCD Screen ---
$pnlLCDScreen           = New-Object System.Windows.Forms.Panel
$pnlLCDScreen.Location  = New-Object System.Drawing.Point(8, 8)
$pnlLCDScreen.Size      = New-Object System.Drawing.Size(540, 124)
$pnlLCDScreen.BackColor = $clrLCDBg
Enable-DoubleBuffer $pnlLCDScreen
$pnlLCDScreen.Add_Paint({
    param($sender, $e)
    $g  = $e.Graphics
    $sw = $sender.Width; $sh = $sender.Height
    $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(14,0,0,0))
    for ($row = 0; $row -lt $sh; $row += 2) { $g.FillRectangle($sb, 0, $row, $sw, 1) }
    $sb.Dispose()
    $vp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,0,0,0), 8)
    $g.DrawRectangle($vp, 0, 0, $sw-1, $sh-1)
    $vp.Dispose()
})
$pnlLCDBezel.Controls.Add($pnlLCDScreen)

$lblLCDFelix           = New-Object System.Windows.Forms.Label
$lblLCDFelix.Location  = New-Object System.Drawing.Point(8, 4)
$lblLCDFelix.Size      = New-Object System.Drawing.Size(524, 82)
$lblLCDFelix.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblLCDFelix.ForeColor = $clrLCDText
$lblLCDFelix.BackColor = [System.Drawing.Color]::Transparent
$lblLCDFelix.AutoSize  = $false
$pnlLCDScreen.Controls.Add($lblLCDFelix)

$lblLCDStatus           = New-Object System.Windows.Forms.Label
$lblLCDStatus.Location  = New-Object System.Drawing.Point(8, 88)
$lblLCDStatus.Size      = New-Object System.Drawing.Size(524, 30)
$lblLCDStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblLCDStatus.ForeColor = $clrLCDAmber
$lblLCDStatus.BackColor = [System.Drawing.Color]::Transparent
$lblLCDStatus.AutoSize  = $false
$lblLCDStatus.Text      = "MODE: IDLE  |  Felix is curled up, dreaming of F-keys..."
$pnlLCDScreen.Controls.Add($lblLCDStatus)

# --- Interval panel ---
$pnlInterval           = New-Object System.Windows.Forms.Panel
$pnlInterval.Location  = New-Object System.Drawing.Point(12, 208)
$pnlInterval.Size      = New-Object System.Drawing.Size(556, 62)
$pnlInterval.BackColor = $clrInputBg
Enable-DoubleBuffer $pnlInterval

function Add-InputLabel($txt, $x, $y, $w=140) {
    $l           = New-Object System.Windows.Forms.Label
    $l.Text      = $txt
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, 18)
    $l.Font      = New-Object System.Drawing.Font("Consolas", 7)
    $l.ForeColor = $clrInputLabel
    $l.BackColor = [System.Drawing.Color]::Transparent
    $pnlInterval.Controls.Add($l)
}
Add-InputLabel "INTERVAL (SEC)" 8   20
Add-InputLabel "RANDOM"         278 20 80
Add-InputLabel "TO"             406 20 24
Add-InputLabel "SEC"            494 20 40

$numNormal          = New-Object System.Windows.Forms.NumericUpDown
$numNormal.Minimum  = 1; $numNormal.Maximum = 86400; $numNormal.Value = 60
$numNormal.Size     = New-Object System.Drawing.Size(72, 22)
Style-NUD $numNormal
$pnlInterval.Controls.Add((Wrap-NUD $numNormal 156 18))

$numRandMin         = New-Object System.Windows.Forms.NumericUpDown
$numRandMin.Minimum = 1; $numRandMin.Maximum = 86400; $numRandMin.Value = 10
$numRandMin.Size    = New-Object System.Drawing.Size(64, 22)
Style-NUD $numRandMin
$pnlInterval.Controls.Add((Wrap-NUD $numRandMin 338 18))

$numRandMax         = New-Object System.Windows.Forms.NumericUpDown
$numRandMax.Minimum = 1; $numRandMax.Maximum = 86400; $numRandMax.Value = 120
$numRandMax.Size    = New-Object System.Drawing.Size(64, 22)
Style-NUD $numRandMax
$pnlInterval.Controls.Add((Wrap-NUD $numRandMax 426 18))

$form.Controls.Add($pnlInterval)

# --- Pad buttons ---
# EP-133 olive pad palette — all pads share the same dark olive rubber base,
# differentiated by text color only (like the actual device)
$btnNormal = New-PadButton `
    -Text "(=^.^=) GENTLE BOOP" -SubText "normal interval" `
    -X 12 -Y 276 -W 268 -H 78 `
    -ColorTop    ([System.Drawing.Color]::FromArgb(64, 80, 44)) `
    -ColorBottom ([System.Drawing.Color]::FromArgb(34, 44, 22)) `
    -ColorText   ([System.Drawing.Color]::FromArgb(168,230,110)) `
    -ColorBorder ([System.Drawing.Color]::FromArgb(48, 62, 30))

$btnRandom = New-PadButton `
    -Text "(>^.^<) SURPRISE!" -SubText "random interval" `
    -X 292 -Y 276 -W 268 -H 78 `
    -ColorTop    ([System.Drawing.Color]::FromArgb(54, 80, 58)) `
    -ColorBottom ([System.Drawing.Color]::FromArgb(28, 44, 32)) `
    -ColorText   ([System.Drawing.Color]::FromArgb(140,220,168)) `
    -ColorBorder ([System.Drawing.Color]::FromArgb(38, 62, 42))

$btnStop = New-PadButton `
    -Text "(=x.x=) HALT FELIX" -SubText "stop timers" `
    -X 12 -Y 364 -W 268 -H 78 `
    -ColorTop    ([System.Drawing.Color]::FromArgb(80, 56, 36)) `
    -ColorBottom ([System.Drawing.Color]::FromArgb(44, 28, 18)) `
    -ColorText   ([System.Drawing.Color]::FromArgb(240,160, 80)) `
    -ColorBorder ([System.Drawing.Color]::FromArgb(60, 38, 22))
$btnStop.Enabled = $false

$btnPokeOnce = New-PadButton `
    -Text "(=^-.^=) POKE ONCE" -SubText "manual trigger" `
    -X 292 -Y 364 -W 268 -H 78 `
    -ColorTop    ([System.Drawing.Color]::FromArgb(80, 72, 36)) `
    -ColorBottom ([System.Drawing.Color]::FromArgb(44, 38, 18)) `
    -ColorText   ([System.Drawing.Color]::FromArgb(240,210, 90)) `
    -ColorBorder ([System.Drawing.Color]::FromArgb(60, 52, 24))

$btnExit = New-PadButton `
    -Text "(=^v^=)  CLOSE & FEED FELIX" `
    -X 12 -Y 452 -W 548 -H 48 `
    -ColorTop    ([System.Drawing.Color]::FromArgb(56, 64, 38)) `
    -ColorBottom ([System.Drawing.Color]::FromArgb(28, 34, 18)) `
    -ColorText   ([System.Drawing.Color]::FromArgb(195,215,145)) `
    -ColorBorder ([System.Drawing.Color]::FromArgb(40, 48, 26))

$form.Controls.Add($btnNormal)
$form.Controls.Add($btnRandom)
$form.Controls.Add($btnStop)
$form.Controls.Add($btnPokeOnce)
$form.Controls.Add($btnExit)

# --- Boop log ---
$lblLog           = New-Object System.Windows.Forms.Label
$lblLog.Text      = "BOOP LOG"
$lblLog.Location  = New-Object System.Drawing.Point(12, 508)
$lblLog.Size      = New-Object System.Drawing.Size(200, 18)
$lblLog.Font      = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
$lblLog.ForeColor = $clrOrange
$lblLog.BackColor = $clrFormBg
$form.Controls.Add($lblLog)

$rtbLog              = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location     = New-Object System.Drawing.Point(12, 530)
$rtbLog.Size         = New-Object System.Drawing.Size(548, 192)
$rtbLog.ReadOnly     = $true
$rtbLog.BackColor    = $clrLogBg
$rtbLog.ForeColor    = [System.Drawing.Color]::FromArgb(100,140,100)
$rtbLog.Font         = New-Object System.Drawing.Font("Consolas", 8.5)
$rtbLog.ScrollBars   = 'Vertical'
$rtbLog.BorderStyle  = 'FixedSingle'
$form.Controls.Add($rtbLog)

Enable-DoubleBuffer $form

# ==================== ANIMATION ====================

$framesIdle = @(
    @("  /\_/\   FELIX           ",
      " ( -.- )  KEY PUSHER      ",
      "  > ^ <   [ IDLE ]        ",
      " /|   |\  . . . . . . .   ",
      "  ~~---~~ . . . . . . .   "),
    @("  /\_/\   FELIX           ",
      " ( -.- )  KEY PUSHER      ",
      "  > ^ <   [ IDLE ]        ",
      " /|   |\  . . z Z z . .   ",
      "  ~~---~~ . . . . . . .   ")
)

$framesActive = @(
    @("  /\_/\   FELIX           ",
      " ( o.o )  KEY PUSHER      ",
      "  > ^ <   [ ARMED ]       ",
      " /|   |\  * * * * * * *   ",
      "  ~~---~~ * * * * * * *   "),
    @("  /\^/\   FELIX           ",
      " ( O.O )  KEY PUSHER      ",
      "  > ^ <   [ ARMED ]       ",
      " /|   |\  * * * * * * *   ",
      "  ~~---~~ * * * * * * *   ")
)

$framesBoop = @(
    @("  \^.^/   FELIX           ",
      "  (^w^)   KEY PUSHER      ",
      "  /| |\   [ BOOP! ]       ",
      " / | | \  ! ! ! ! ! ! !   ",
      " ~~|=|~~  ! ! ! ! ! ! !   "),
    @("  /^.^\   FELIX           ",
      "  (>w<)   KEY PUSHER      ",
      "  /| |\   [ BOOP! ]       ",
      " / | | \  ! ! ! ! ! ! !   ",
      " ~~|=|~~  ! ! ! ! ! ! !   ")
)

$framesMiss = @(
    @("  /\_/\   FELIX           ",
      " ( o.O )  KEY PUSHER      ",
      "  > ? <   [ MISS ]        ",
      " /|   |\  ? ? ? ? ? ? ?   ",
      "  ~~---~~ ? ? ? ? ? ? ?   "),
    @("  /\_/\   FELIX           ",
      " ( -.- )  KEY PUSHER      ",
      "  > ? <   [ MISS ]        ",
      " /|   |\  ? ? ? ? ? ? ?   ",
      "  ~~---~~ ? ? ? ? ? ? ?   ")
)

$script:animState = "Idle"
$script:animFrame = 0

function Update-LEDs {
    param($state)
    switch ($state) {
        "Idle"   { $script:led1.Tag = [System.Drawing.Color]::FromArgb(30, 60,25)
                   $script:led2.Tag = [System.Drawing.Color]::FromArgb(60, 50,15) }
        "Active" { $script:led1.Tag = [System.Drawing.Color]::FromArgb(80,220,60)
                   $script:led2.Tag = [System.Drawing.Color]::FromArgb(60, 50,15) }
        "Boop"   { $script:led1.Tag = [System.Drawing.Color]::FromArgb(80,220,60)
                   $script:led2.Tag = [System.Drawing.Color]::FromArgb(220,180,40) }
        "Miss"   { $script:led1.Tag = [System.Drawing.Color]::FromArgb(30, 60,25)
                   $script:led2.Tag = [System.Drawing.Color]::FromArgb(180, 80,20) }
    }
    $script:led1.Invalidate(); $script:led2.Invalidate()
}

function Set-AnimState {
    param($state)
    $script:animState = $state
    $script:animFrame = 0
    switch ($state) {
        "Boop"  { $script:animTimer.Interval = 300 }
        "Miss"  { $script:animTimer.Interval = 800 }
        default { $script:animTimer.Interval = 600 }
    }
    Update-LEDs $state
}

$script:animTimer = New-Object System.Windows.Forms.Timer
$script:animTimer.Interval = 600
$script:animTimer.Add_Tick({
    $frames = switch ($script:animState) {
        "Idle"   { $framesIdle   }
        "Active" { $framesActive }
        "Boop"   { $framesBoop   }
        "Miss"   { $framesMiss   }
        default  { $framesIdle   }
    }
    $script:animFrame = ($script:animFrame + 1) % $frames.Count
    $lblLCDFelix.Text = $frames[$script:animFrame] -join "`n"
})
$script:animTimer.Start()
$lblLCDFelix.Text = $framesIdle[0] -join "`n"

# Revert-to-previous-state timer (single instance, reused)
$script:revertTarget = "Idle"
$script:revertTimer  = New-Object System.Windows.Forms.Timer
$script:revertTimer.Add_Tick({
    $script:revertTimer.Stop()
    Set-AnimState $script:revertTarget
})

# ==================== LOGIC ====================

$script:winFormsTimer = $null
$script:threadTimer   = $null
$script:mode          = "Idle"
$rand                 = New-Object System.Random

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

function Add-BoopLog {
    param($text)
    $color = switch -Regex ($text) {
        'BOOP!'  { [System.Drawing.Color]::FromArgb(140,220,140) }
        'MISS'   { [System.Drawing.Color]::FromArgb(210,155, 50) }
        'ERROR'  { [System.Drawing.Color]::FromArgb(220, 80, 60) }
        default  { [System.Drawing.Color]::FromArgb(100,140,100) }
    }
    $rtbLog.SelectionStart  = $rtbLog.TextLength
    $rtbLog.SelectionLength = 0
    $rtbLog.SelectionColor  = $color
    $rtbLog.AppendText($text + "`n")
    $rtbLog.ScrollToCaret()
}

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
            $form.Invoke([action]{ $lblLCDStatus.Text = "TEAMS NOT FOUND  |  (=^o.o^=)? Felix is confused." })
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
            $form.Invoke([action]{ $lblLCDStatus.Text = "FOCUS FAILED  |  $($_.Exception.Message)" })
        }
        return $false
    }
}

function Send-F15 {
    param($reason)
    try {
        $focused = Focus-Teams $true
        $time    = Get-Date -Format "HH:mm:ss"
        if (-not $focused) {
            $form.Invoke([action]{
                $lblLCDStatus.Text = "MODE: $($script:mode)  |  $time  |  Teams not found. Felix sighs."
                Add-BoopLog "[$time] MISS  | Teams not found ($reason)"
                Set-AnimState "Miss"
                $script:revertTarget  = if ($script:mode -eq "Idle") { "Idle" } else { "Active" }
                $script:revertTimer.Interval = 2400
                $script:revertTimer.Stop(); $script:revertTimer.Start()
            })
            return
        }
        [System.Windows.Forms.SendKeys]::SendWait("{F15}")
        $quip = if ($rand.Next(1,4) -eq 2) { $quips[$rand.Next(0,$quips.Count)] } else { "Felix reports success! (=^v^=)" }
        $form.Invoke([action]{
            $lblLCDStatus.Text = "MODE: $($script:mode)  |  $time  |  $quip"
            Add-BoopLog "[$time] BOOP! | $reason | $quip"
            Set-AnimState "Boop"
            $script:revertTarget  = if ($script:mode -eq "Idle") { "Idle" } else { "Active" }
            $script:revertTimer.Interval = 1200
            $script:revertTimer.Stop(); $script:revertTimer.Start()
        })
    } catch {
        $form.Invoke([action]{
            $lblLCDStatus.Text = "ERROR  |  $($_.Exception.Message)"
            Add-BoopLog "[$(Get-Date -Format 'HH:mm:ss')] ERROR | $($_.Exception.Message)"
            Set-AnimState "Miss"
        })
    }
}

function Stop-AllTimers {
    if ($script:winFormsTimer -ne $null) {
        $script:winFormsTimer.Stop()
        $script:winFormsTimer.Dispose()
        $script:winFormsTimer = $null
    }
    if ($script:threadTimer -ne $null) {
        try { $script:threadTimer.Change([System.Threading.Timeout]::Infinite,
                                          [System.Threading.Timeout]::Infinite) } catch {}
        try { $script:threadTimer.Dispose() } catch {}
        $script:threadTimer = $null
    }
    $script:mode = "Idle"
    $form.Invoke([action]{
        $btnStop.Enabled   = $false
        $btnNormal.Enabled = $true
        $btnRandom.Enabled = $true
        $btnStop.Invalidate(); $btnNormal.Invalidate(); $btnRandom.Invalidate()
        $lblLCDStatus.Text = "MODE: IDLE  |  Felix has clocked out. /\_/\"
        Set-AnimState "Idle"
    })
}

# ==================== BUTTON WIRING ====================

$btnNormal.Add_Click({
    Stop-AllTimers
    $intervalSec     = [int]$numNormal.Value
    $script:mode     = "NORMAL"
    $form.Invoke([action]{
        $btnStop.Enabled   = $true
        $btnNormal.Enabled = $false
        $btnRandom.Enabled = $false
        $btnStop.Invalidate(); $btnNormal.Invalidate(); $btnRandom.Invalidate()
        Set-AnimState "Active"
    })
    $script:winFormsTimer          = New-Object System.Windows.Forms.Timer
    $script:winFormsTimer.Interval = $intervalSec * 1000
    $script:winFormsTimer.Add_Tick({ Send-F15 "Normal interval $([int]$numNormal.Value)s" })
    Send-F15 "Normal start (immediate)"
    $script:winFormsTimer.Start()
    $form.Invoke([action]{ $lblLCDStatus.Text = "MODE: NORMAL  |  Every ${intervalSec}s  |  Felix on duty. (=^-.^=)" })
})

$btnRandom.Add_Click({
    Stop-AllTimers
    $minSec      = [int]$numRandMin.Value
    $maxSec      = [int]$numRandMax.Value
    if ($minSec -gt $maxSec) { $tmp = $minSec; $minSec = $maxSec; $maxSec = $tmp }
    $script:mode = "RANDOM"
    $form.Invoke([action]{
        $btnStop.Enabled   = $true
        $btnNormal.Enabled = $false
        $btnRandom.Enabled = $false
        $btnStop.Invalidate(); $btnNormal.Invalidate(); $btnRandom.Invalidate()
        Set-AnimState "Active"
        $lblLCDStatus.Text = "MODE: RANDOM  |  Felix is plotting surprises... (>^.^<)"
    })
    $callback = [System.Threading.TimerCallback]{
        param($state)
        $form.Invoke([action]{ Send-F15 "Random mode" })
        $next = $rand.Next($minSec, $maxSec + 1)
        try {
            $script:threadTimer.Change($next * 1000, [System.Threading.Timeout]::Infinite) | Out-Null
            $form.Invoke([action]{ $lblLCDStatus.Text = "MODE: RANDOM  |  Next poke in ${next}s  |  Felix giggles." })
        } catch {}
    }
    $script:threadTimer = New-Object System.Threading.Timer(
        $callback, $null,
        [System.Threading.Timeout]::Infinite,
        [System.Threading.Timeout]::Infinite)
    Send-F15 "Random start (immediate)"
    $nextInitial = $rand.Next($minSec, $maxSec + 1)
    $script:threadTimer.Change($nextInitial * 1000, [System.Threading.Timeout]::Infinite) | Out-Null
    $form.Invoke([action]{ $lblLCDStatus.Text = "MODE: RANDOM  |  First poke in ${nextInitial}s  |  Felix hides a squeaky toy." })
})

$btnPokeOnce.Add_Click({ Send-F15 "Manual poke" })
$btnStop.Add_Click({ Stop-AllTimers })
$btnExit.Add_Click({ Stop-AllTimers; $form.Close() })

$form.Add_FormClosing({
    Stop-AllTimers
    $script:animTimer.Stop()
    $script:revertTimer.Stop()
})

Add-BoopLog "[$(Get-Date -Format 'HH:mm:ss')] Felix is ready. Awaiting orders... (=^.^=)"

[void]$form.ShowDialog()
