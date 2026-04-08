Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide the PowerShell console window so only the GUI is visible
Add-Type -Name ConsoleUtils -Namespace Win32 -MemberDefinition '
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'
[Win32.ConsoleUtils]::ShowWindow([Win32.ConsoleUtils]::GetConsoleWindow(), 0) | Out-Null

# ===== THEME: BLUE CYBERPUNK =====
$clrBg     = [System.Drawing.Color]::FromArgb(10,  14,  26)
$clrPanel  = [System.Drawing.Color]::FromArgb(15,  20,  38)
$clrCyan   = [System.Drawing.Color]::FromArgb(0,   255, 255)
$clrBlue   = [System.Drawing.Color]::FromArgb(68,  136, 255)
$clrDim    = [System.Drawing.Color]::FromArgb(100, 160, 200)
$clrLog    = [System.Drawing.Color]::FromArgb(126, 200, 227)
$clrAmber  = [System.Drawing.Color]::FromArgb(255, 183, 0)
$clrRed    = [System.Drawing.Color]::FromArgb(255, 68,  68)
$clrBtnBg  = [System.Drawing.Color]::FromArgb(26,  32,  64)
$clrBtnBrd = [System.Drawing.Color]::FromArgb(0,   180, 220)

$fntMono8  = New-Object System.Drawing.Font("Courier New", 8,  [System.Drawing.FontStyle]::Regular)
$fntMono9  = New-Object System.Drawing.Font("Courier New", 9,  [System.Drawing.FontStyle]::Regular)
$fntMono9B = New-Object System.Drawing.Font("Courier New", 9,  [System.Drawing.FontStyle]::Bold)
$fntMono11 = New-Object System.Drawing.Font("Courier New", 11, [System.Drawing.FontStyle]::Bold)
$fntMono14 = New-Object System.Drawing.Font("Courier New", 14, [System.Drawing.FontStyle]::Bold)

# ===== STATE =====
$script:emails  = @()
$script:apiKey  = $env:ANTHROPIC_API_KEY
$script:isBusy  = $false
$script:quipIdx = 0

# ===== QUIPS =====
$script:quips = @(
    "R.E.A.D. has scanned your inbox. Efficiency: optimal.",
    "Processing... beep boop... your emails are sorted.",
    "Awaiting your command, operator. Standing by.",
    "Memory banks updated. All systems nominal.",
    "R.E.A.D. does not sleep. R.E.A.D. only reads.",
    "Inbox analysis complete. Humans write too much.",
    "Threat level: 0. Unread count: critical. As usual.",
    "R.E.A.D. recommends more concise subject lines.",
    "Calculating optimal response order... done.",
    "No emotions detected. Just emails. Proceeding.",
    "R.E.A.D. has opinions about reply-all. Negative.",
    "Scanning for urgent items... beep... boop... done.",
    "Briefing generation initiated. Please stand by.",
    "R.E.A.D. is a professional. R.E.A.D. is judging you.",
    "All systems go. Your inbox, however, is another matter."
)

# ===== SYSTEM PROMPTS =====
$script:sysEmail = @"
You are R.E.A.D. (Robotic Email Assistant Droid), a precise and deadpan AI assistant.
Analyze the provided emails and produce a structured briefing.
Use plain ASCII only. Max 80 chars per line. Be concise and matter-of-fact.
No emojis, no markdown, no special characters beyond hyphens, brackets, equals signs.
Use ONLY these section headers (skip sections that do not apply):
  [!] PRIORITY ALERTS
  [>] ACTION REQUIRED
  [i] FYI / INFORMATIONAL
  [=] DAILY ASSESSMENT
  [#] RECOMMENDED RESPONSE ORDER
"@

$script:sysNews = @"
You are R.E.A.D. (Robotic Email Assistant Droid), a neutral and deadpan news analyst.
Summarize the provided headlines into a concise briefing. No opinions, no editorializing.
Group by topic where logical. Plain ASCII only, 80-char line limit.
Use these section headers:
  [TOP] TOP 5 MOST SIGNIFICANT STORIES
  [GRP] GROUPED TOPIC SUMMARY
  [=]   OVERALL ASSESSMENT
"@

# ===== HELPER FUNCTIONS =====

function New-CyberButton {
    param([string]$text, [int]$x, [int]$y, [int]$w, [int]$h)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text                           = $text
    $btn.Location                       = New-Object System.Drawing.Point($x, $y)
    $btn.Size                           = New-Object System.Drawing.Size($w, $h)
    $btn.FlatStyle                      = 'Flat'
    $btn.BackColor                      = $clrBtnBg
    $btn.ForeColor                      = $clrCyan
    $btn.Font                           = $fntMono9B
    $btn.FlatAppearance.BorderSize      = 1
    $btn.FlatAppearance.BorderColor     = $clrBtnBrd
    $btn.Cursor                         = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Add-Log {
    param([string]$text)
    $time = Get-Date -Format "HH:mm:ss"
    $line = "[$time] $text"
    $form.Invoke([action]{
        $rtbLog.AppendText($line + "`n")
        $rtbLog.ScrollToCaret()
    })
}

function Append-BriefingLine {
    param([string]$line)
    $color = $clrCyan
    if     ($line -match '^\[!\]')               { $color = $clrAmber }
    elseif ($line -match '^\[>\]')               { $color = $clrCyan  }
    elseif ($line -match '^\[i\]')               { $color = $clrBlue  }
    elseif ($line -match '^\[=\]')               { $color = $clrDim   }
    elseif ($line -match '^\[#\]')               { $color = $clrLog   }
    elseif ($line -match '^\[TOP\]')             { $color = $clrAmber }
    elseif ($line -match '^\[GRP\]')             { $color = $clrBlue  }
    elseif ($line -match '^={3,}$|^-{3,}$')     { $color = $clrDim   }
    elseif ($line -match '^R\.E\.A\.D\. TERMINAL') { $color = $clrAmber }
    $rtbBriefing.Select($rtbBriefing.TextLength, 0)
    $rtbBriefing.SelectionColor = $color
    $rtbBriefing.AppendText($line + "`n")
    $rtbBriefing.ScrollToCaret()
}

function Show-ApiKeyDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "R.E.A.D. -- API KEY REQUIRED"
    $dlg.Size            = New-Object System.Drawing.Size(480, 205)
    $dlg.StartPosition   = "CenterParent"
    $dlg.BackColor       = $clrBg
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = "ANTHROPIC_API_KEY not set. Enter key to proceed:"
    $lbl.Location  = New-Object System.Drawing.Point(12, 18)
    $lbl.Size      = New-Object System.Drawing.Size(445, 20)
    $lbl.Font      = $fntMono9
    $lbl.ForeColor = $clrCyan
    $lbl.BackColor = $clrBg
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location              = New-Object System.Drawing.Point(12, 46)
    $txt.Size                  = New-Object System.Drawing.Size(445, 24)
    $txt.BackColor             = [System.Drawing.Color]::FromArgb(20, 28, 52)
    $txt.ForeColor             = $clrCyan
    $txt.Font                  = $fntMono9
    $txt.UseSystemPasswordChar = $true
    $txt.BorderStyle           = 'FixedSingle'
    $dlg.Controls.Add($txt)

    $btnOk = New-CyberButton "[CONFIRM]" 12 88 110 32
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOk)

    $btnSkip = New-CyberButton "[SKIP]" 130 88 90 32
    $btnSkip.ForeColor    = $clrDim
    $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnSkip)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnSkip

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $txt.Text.Trim()
    }
    return $null
}

function Initialize-ApiKey {
    if (-not [string]::IsNullOrEmpty($script:apiKey)) { return $true }
    $key = Show-ApiKeyDialog
    if ([string]::IsNullOrEmpty($key)) {
        Add-Log "[WARN] No API key provided. AI features unavailable."
        $form.Invoke([action]{ $lblApiStatus.ForeColor = $clrAmber })
        return $false
    }
    $script:apiKey = $key
    Add-Log "[OK] API key accepted."
    $form.Invoke([action]{
        $lblApiStatus.Text      = "API KEY: SET  |  R.E.A.D. is ready"
        $lblApiStatus.ForeColor = $clrLog
    })
    return $true
}

function ConvertTo-PlainText {
    param([string]$body)
    $body = $body -replace '<[^>]+>', ' '
    $body = $body -replace '\s+', ' '
    $body = $body.Trim()
    if ($body.Length -gt 400) { $body = $body.Substring(0, 400) + "..." }
    return $body
}

function Get-OutlookEmails {
    $outlook = $null
    try {
        $outlook = [System.Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application")
    } catch {
        try { $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop }
        catch { throw "Outlook is not running and could not be started." }
    }
    $ns    = $outlook.GetNamespace("MAPI")
    $inbox = $ns.GetDefaultFolder(6)
    $items = $inbox.Items
    $items.Sort("[ReceivedTime]", $true)

    $result = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($item in $items) {
        if ($item.Class -eq 43 -and $item.UnRead) {
            $result.Add([PSCustomObject]@{
                From     = $item.SenderName
                Email    = $item.SenderEmailAddress
                Subject  = if ($item.Subject) { $item.Subject } else { "(no subject)" }
                Received = $item.ReceivedTime
                Body     = ConvertTo-PlainText $item.Body
            })
            if ($result.Count -ge 50) { break }
        }
    }
    return $result
}

function Build-EmailPrompt {
    param([object]$emails)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Unread emails to analyze: $($emails.Count)")
    [void]$sb.AppendLine("Briefing requested: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    [void]$sb.AppendLine("=" * 60)
    $i = 1
    foreach ($e in $emails) {
        [void]$sb.AppendLine("--- EMAIL $i ---")
        [void]$sb.AppendLine("FROM: $($e.From) <$($e.Email)>")
        [void]$sb.AppendLine("SUBJECT: $($e.Subject)")
        [void]$sb.AppendLine("RECEIVED: $($e.Received.ToString('yyyy-MM-dd HH:mm'))")
        [void]$sb.AppendLine("PREVIEW: $($e.Body)")
        [void]$sb.AppendLine()
        $i++
    }
    return $sb.ToString()
}

function Invoke-ClaudeApi {
    param(
        [string]$systemPrompt,
        [string]$userContent,
        [int]$maxTokens = 1200
    )
    $headers = @{
        "x-api-key"         = $script:apiKey
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }
    $body = @{
        model      = "claude-opus-4-6"
        max_tokens = $maxTokens
        system     = $systemPrompt
        messages   = @(@{ role = "user"; content = $userContent })
    } | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod `
        -Uri         "https://api.anthropic.com/v1/messages" `
        -Method      Post `
        -Headers     $headers `
        -Body        $body `
        -ErrorAction Stop
    return $response.content[0].text
}

function Get-NewsHeadlines {
    $sources = @(
        @{ Name = "REUTERS"; Url = "https://feeds.reuters.com/reuters/topNews" },
        @{ Name = "BBC";     Url = "https://feeds.bbci.co.uk/news/rss.xml"    },
        @{ Name = "NPR";     Url = "https://feeds.npr.org/1001/rss.xml"       }
    )
    $headlines = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($src in $sources) {
        try {
            $rss   = Invoke-RestMethod -Uri $src.Url -ErrorAction Stop -TimeoutSec 12
            $items = $rss.channel.item | Select-Object -First 8
            foreach ($item in $items) {
                $title = ($item.title -replace '<[^>]+>', '').Trim()
                if ($title) {
                    $headlines.Add([PSCustomObject]@{
                        Source = $src.Name
                        Title  = $title
                        Date   = $item.pubDate
                    })
                }
            }
            Add-Log "[OK] $($src.Name): $($items.Count) headlines fetched"
        } catch {
            Add-Log "[WARN] $($src.Name): fetch failed -- $($_.Exception.Message)"
        }
    }
    return $headlines
}

function Build-NewsPrompt {
    param([object]$headlines)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("NEWS HEADLINES -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    [void]$sb.AppendLine("=" * 60)
    foreach ($h in $headlines) {
        [void]$sb.AppendLine("[$($h.Source)] $($h.Title)")
    }
    return $sb.ToString()
}

function Set-Busy {
    param([bool]$busy)
    $script:isBusy = $busy
    $form.Invoke([action]{
        $btnScan.Enabled  = -not $busy
        $btnBrief.Enabled = -not $busy
        $btnNews.Enabled  = -not $busy
        $btnClear.Enabled = -not $busy
    })
}

# ===== FORM =====

$form = New-Object System.Windows.Forms.Form
$form.Text            = "R.E.A.D. TERMINAL v1.0"
$form.Size            = New-Object System.Drawing.Size(780, 860)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.BackColor       = $clrBg

# -- Robot mascot panel (top-left) --
$pnlRobot = New-Object System.Windows.Forms.Panel
$pnlRobot.Location    = New-Object System.Drawing.Point(10, 8)
$pnlRobot.Size        = New-Object System.Drawing.Size(200, 185)
$pnlRobot.BackColor   = $clrPanel
$pnlRobot.BorderStyle = 'FixedSingle'
$form.Controls.Add($pnlRobot)

$robotArt = @"
   .-----------.
  | [O]   [O] |
  |    -----   |
  |   \ ___ /  |
  |    |   |   |
   '-----------'
  .-----------.
  | R.E.A.D. |
  | UNIT MK-7|
  '-----------'
      | | |
   .--++++--.
   |         |
   '---------'
    |       |
"@

$lblRobot = New-Object System.Windows.Forms.Label
$lblRobot.Text      = $robotArt
$lblRobot.Font      = $fntMono8
$lblRobot.ForeColor = $clrCyan
$lblRobot.BackColor = $clrPanel
$lblRobot.AutoSize  = $false
$lblRobot.Size      = New-Object System.Drawing.Size(196, 182)
$lblRobot.Location  = New-Object System.Drawing.Point(2, 2)
$pnlRobot.Controls.Add($lblRobot)

# -- Title area (top-right) --
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "R.E.A.D. TERMINAL  v1.0"
$lblTitle.Font      = $fntMono14
$lblTitle.ForeColor = $clrCyan
$lblTitle.BackColor = $clrBg
$lblTitle.AutoSize  = $false
$lblTitle.Size      = New-Object System.Drawing.Size(548, 34)
$lblTitle.Location  = New-Object System.Drawing.Point(218, 10)
$form.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text      = "Robotic Email Assistant Droid"
$lblSubtitle.Font      = $fntMono9
$lblSubtitle.ForeColor = $clrDim
$lblSubtitle.BackColor = $clrBg
$lblSubtitle.AutoSize  = $false
$lblSubtitle.Size      = New-Object System.Drawing.Size(548, 18)
$lblSubtitle.Location  = New-Object System.Drawing.Point(218, 46)
$form.Controls.Add($lblSubtitle)

$sepTitle = New-Object System.Windows.Forms.Label
$sepTitle.BorderStyle = 'Fixed3D'
$sepTitle.Size        = New-Object System.Drawing.Size(548, 2)
$sepTitle.Location    = New-Object System.Drawing.Point(218, 69)
$form.Controls.Add($sepTitle)

$lblClock = New-Object System.Windows.Forms.Label
$lblClock.Text      = Get-Date -Format "HH:mm:ss  |  ddd  dd MMM yyyy"
$lblClock.Font      = $fntMono11
$lblClock.ForeColor = $clrBlue
$lblClock.BackColor = $clrBg
$lblClock.AutoSize  = $false
$lblClock.Size      = New-Object System.Drawing.Size(548, 26)
$lblClock.Location  = New-Object System.Drawing.Point(218, 77)
$form.Controls.Add($lblClock)

$lblQuip = New-Object System.Windows.Forms.Label
$lblQuip.Text      = $script:quips[0]
$lblQuip.Font      = $fntMono9
$lblQuip.ForeColor = $clrLog
$lblQuip.BackColor = $clrBg
$lblQuip.AutoSize  = $false
$lblQuip.Size      = New-Object System.Drawing.Size(548, 100)
$lblQuip.Location  = New-Object System.Drawing.Point(218, 110)
$form.Controls.Add($lblQuip)

# -- Separator 1 --
$sep1 = New-Object System.Windows.Forms.Label
$sep1.BorderStyle = 'Fixed3D'
$sep1.Size        = New-Object System.Drawing.Size(756, 2)
$sep1.Location    = New-Object System.Drawing.Point(10, 200)
$form.Controls.Add($sep1)

# -- Email count --
$lblEmailCount = New-Object System.Windows.Forms.Label
$lblEmailCount.Text      = "INBOX: no scan performed"
$lblEmailCount.Font      = $fntMono9
$lblEmailCount.ForeColor = $clrDim
$lblEmailCount.BackColor = $clrBg
$lblEmailCount.AutoSize  = $false
$lblEmailCount.Size      = New-Object System.Drawing.Size(580, 20)
$lblEmailCount.Location  = New-Object System.Drawing.Point(10, 210)
$form.Controls.Add($lblEmailCount)

# -- Buttons row 1 --
$btnScan  = New-CyberButton "[SCAN INBOX]"        10  234 148 34
$btnBrief = New-CyberButton "[GENERATE BRIEFING]" 166 234 188 34
$btnNews  = New-CyberButton "[GET NEWS]"          362 234 118 34
$form.Controls.Add($btnScan)
$form.Controls.Add($btnBrief)
$form.Controls.Add($btnNews)

# -- Buttons row 2 --
$btnClear = New-CyberButton "[CLEAR]" 10  276 100 30
$btnClear.ForeColor = $clrDim
$btnExit  = New-CyberButton "[EXIT]"  118 276  90 30
$btnExit.ForeColor                      = $clrRed
$btnExit.FlatAppearance.BorderColor     = $clrRed
$form.Controls.Add($btnClear)
$form.Controls.Add($btnExit)

# -- API status --
$apiStatusTxt = if ($script:apiKey) {
    "API KEY: SET  |  R.E.A.D. is ready to generate briefings"
} else {
    "API KEY: NOT SET  |  Set ANTHROPIC_API_KEY or enter key when prompted"
}
$lblApiStatus = New-Object System.Windows.Forms.Label
$lblApiStatus.Text      = $apiStatusTxt
$lblApiStatus.Font      = $fntMono8
$lblApiStatus.ForeColor = if ($script:apiKey) { $clrLog } else { $clrAmber }
$lblApiStatus.BackColor = $clrBg
$lblApiStatus.AutoSize  = $false
$lblApiStatus.Size      = New-Object System.Drawing.Size(756, 18)
$lblApiStatus.Location  = New-Object System.Drawing.Point(10, 315)
$form.Controls.Add($lblApiStatus)

# -- Separator 2 --
$sep2 = New-Object System.Windows.Forms.Label
$sep2.BorderStyle = 'Fixed3D'
$sep2.Size        = New-Object System.Drawing.Size(756, 2)
$sep2.Location    = New-Object System.Drawing.Point(10, 340)
$form.Controls.Add($sep2)

# -- Briefing header --
$lblBriefHdr = New-Object System.Windows.Forms.Label
$lblBriefHdr.Text      = "BRIEFING OUTPUT"
$lblBriefHdr.Font      = $fntMono9B
$lblBriefHdr.ForeColor = $clrCyan
$lblBriefHdr.BackColor = $clrBg
$lblBriefHdr.AutoSize  = $false
$lblBriefHdr.Size      = New-Object System.Drawing.Size(200, 18)
$lblBriefHdr.Location  = New-Object System.Drawing.Point(10, 348)
$form.Controls.Add($lblBriefHdr)

# -- Briefing RichTextBox --
$rtbBriefing = New-Object System.Windows.Forms.RichTextBox
$rtbBriefing.Location    = New-Object System.Drawing.Point(10, 368)
$rtbBriefing.Size        = New-Object System.Drawing.Size(750, 265)
$rtbBriefing.ReadOnly    = $true
$rtbBriefing.BackColor   = $clrPanel
$rtbBriefing.ForeColor   = $clrCyan
$rtbBriefing.Font        = $fntMono9
$rtbBriefing.ScrollBars  = 'Vertical'
$rtbBriefing.BorderStyle = 'FixedSingle'
$rtbBriefing.WordWrap    = $true
$form.Controls.Add($rtbBriefing)

# -- Separator 3 --
$sep3 = New-Object System.Windows.Forms.Label
$sep3.BorderStyle = 'Fixed3D'
$sep3.Size        = New-Object System.Drawing.Size(756, 2)
$sep3.Location    = New-Object System.Drawing.Point(10, 640)
$form.Controls.Add($sep3)

# -- Log header --
$lblLogHdr = New-Object System.Windows.Forms.Label
$lblLogHdr.Text      = "ACTIVITY LOG"
$lblLogHdr.Font      = $fntMono9B
$lblLogHdr.ForeColor = $clrDim
$lblLogHdr.BackColor = $clrBg
$lblLogHdr.AutoSize  = $false
$lblLogHdr.Size      = New-Object System.Drawing.Size(200, 18)
$lblLogHdr.Location  = New-Object System.Drawing.Point(10, 648)
$form.Controls.Add($lblLogHdr)

# -- Activity log RichTextBox --
$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(10, 668)
$rtbLog.Size        = New-Object System.Drawing.Size(750, 140)
$rtbLog.ReadOnly    = $true
$rtbLog.BackColor   = [System.Drawing.Color]::FromArgb(8, 12, 24)
$rtbLog.ForeColor   = $clrLog
$rtbLog.Font        = $fntMono8
$rtbLog.ScrollBars  = 'Vertical'
$rtbLog.BorderStyle = 'FixedSingle'
$form.Controls.Add($rtbLog)

# ===== EVENT HANDLERS =====

$btnScan.Add_Click({
    if ($script:isBusy) { return }
    Set-Busy $true
    $t = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Add-Log "[SCAN] Connecting to Outlook..."
            $mails = Get-OutlookEmails
            $script:emails = $mails
            $count = $mails.Count
            $truncNote = if ($count -ge 50) { " (capped at 50)" } else { "" }
            Add-Log "[SCAN] Found $count unread email(s)$truncNote."
            $form.Invoke([action]{
                $lblEmailCount.Text      = "INBOX: $count unread email(s) loaded$truncNote"
                $lblEmailCount.ForeColor = if ($count -gt 0) { $clrCyan } else { $clrDim }
            })
        } catch {
            $err = $_.Exception.Message
            Add-Log "[ERROR] $err"
            $form.Invoke([action]{
                $lblEmailCount.Text      = "INBOX: scan failed -- see log"
                $lblEmailCount.ForeColor = $clrRed
            })
        } finally {
            Set-Busy $false
        }
    })
    $t.IsBackground = $true
    $t.Start()
})

$btnBrief.Add_Click({
    if ($script:isBusy) { return }
    if (-not (Initialize-ApiKey)) { return }
    if ($script:emails.Count -eq 0) {
        Add-Log "[WARN] No emails loaded. Run [SCAN INBOX] first."
        return
    }
    Set-Busy $true
    $emailSnapshot = $script:emails
    $t = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Add-Log "[BRIEF] Building prompt for $($emailSnapshot.Count) email(s)..."
            $prompt = Build-EmailPrompt $emailSnapshot
            Add-Log "[BRIEF] Calling Claude API..."
            $result  = Invoke-ClaudeApi $script:sysEmail $prompt 1500
            $ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $divider = "=" * 60
            $form.Invoke([action]{
                $rtbBriefing.Clear()
                Append-BriefingLine $divider
                Append-BriefingLine "R.E.A.D. TERMINAL -- EMAIL BRIEFING"
                Append-BriefingLine "Generated : $ts"
                Append-BriefingLine "Emails    : $($emailSnapshot.Count)"
                Append-BriefingLine $divider
                Append-BriefingLine ""
                foreach ($line in ($result -split "`r?`n")) {
                    Append-BriefingLine $line
                }
                Append-BriefingLine ""
                Append-BriefingLine $divider
                Append-BriefingLine "-- END OF BRIEFING --"
            })
            Add-Log "[BRIEF] Briefing generated successfully."
        } catch {
            $err = $_.Exception.Message
            Add-Log "[ERROR] $err"
            $form.Invoke([action]{
                $rtbBriefing.Clear()
                Append-BriefingLine "[!] BRIEFING GENERATION FAILED"
                Append-BriefingLine "ERROR: $err"
            })
        } finally {
            Set-Busy $false
        }
    })
    $t.IsBackground = $true
    $t.Start()
})

$btnNews.Add_Click({
    if ($script:isBusy) { return }
    Set-Busy $true
    $t = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Add-Log "[NEWS] Fetching headlines from Reuters, BBC, NPR..."
            $headlines = Get-NewsHeadlines
            if ($headlines.Count -eq 0) {
                Add-Log "[NEWS] No headlines retrieved. Check network connection."
                Set-Busy $false
                return
            }
            Add-Log "[NEWS] $($headlines.Count) total headlines retrieved."
            $ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $divider = "=" * 60
            $form.Invoke([action]{
                $rtbBriefing.Clear()
                Append-BriefingLine $divider
                Append-BriefingLine "R.E.A.D. TERMINAL -- NEWS FEED"
                Append-BriefingLine "Retrieved : $ts"
                Append-BriefingLine "Sources   : Reuters / BBC / NPR"
                Append-BriefingLine $divider
                Append-BriefingLine ""
                foreach ($h in $headlines) {
                    Append-BriefingLine "[$($h.Source.PadRight(7))] $($h.Title)"
                }
                Append-BriefingLine ""
                Append-BriefingLine $divider
            })

            # AI summary if key is available
            if (-not [string]::IsNullOrEmpty($script:apiKey)) {
                Add-Log "[NEWS] Generating AI analysis..."
                try {
                    $prompt  = Build-NewsPrompt $headlines
                    $summary = Invoke-ClaudeApi $script:sysNews $prompt 800
                    $form.Invoke([action]{
                        Append-BriefingLine ""
                        Append-BriefingLine "R.E.A.D. TERMINAL -- AI NEWS ANALYSIS"
                        Append-BriefingLine ("=" * 60)
                        foreach ($line in ($summary -split "`r?`n")) {
                            Append-BriefingLine $line
                        }
                        Append-BriefingLine ("=" * 60)
                        Append-BriefingLine "-- END OF NEWS BRIEFING --"
                    })
                    Add-Log "[NEWS] AI analysis complete."
                } catch {
                    Add-Log "[WARN] AI analysis failed: $($_.Exception.Message)"
                    $form.Invoke([action]{
                        Append-BriefingLine "-- END OF NEWS FEED (AI analysis unavailable) --"
                    })
                }
            } else {
                $form.Invoke([action]{
                    Append-BriefingLine "-- END OF NEWS FEED --"
                    Append-BriefingLine "[i] Set ANTHROPIC_API_KEY for AI-powered analysis."
                })
            }
        } catch {
            Add-Log "[ERROR] $($_.Exception.Message)"
        } finally {
            Set-Busy $false
        }
    })
    $t.IsBackground = $true
    $t.Start()
})

$btnClear.Add_Click({
    $rtbBriefing.Clear()
    Add-Log "[CLEAR] Briefing pane cleared."
})

$btnExit.Add_Click({ $form.Close() })

$form.Add_FormClosing({
    $timerClock.Stop(); $timerClock.Dispose()
    $timerQuip.Stop();  $timerQuip.Dispose()
})

# ===== TIMERS =====

$timerClock = New-Object System.Windows.Forms.Timer
$timerClock.Interval = 1000
$timerClock.Add_Tick({
    $lblClock.Text = Get-Date -Format "HH:mm:ss  |  ddd  dd MMM yyyy"
})
$timerClock.Start()

$timerQuip = New-Object System.Windows.Forms.Timer
$timerQuip.Interval = 8000
$timerQuip.Add_Tick({
    $script:quipIdx = ($script:quipIdx + 1) % $script:quips.Count
    $lblQuip.Text   = $script:quips[$script:quipIdx]
})
$timerQuip.Start()

# ===== STARTUP =====
$rtbLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] R.E.A.D. TERMINAL v1.0 initialized. All systems nominal.`n")
if ($script:apiKey) {
    $rtbLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] API key detected from environment. Ready for briefings.`n")
}

[void]$form.ShowDialog()
