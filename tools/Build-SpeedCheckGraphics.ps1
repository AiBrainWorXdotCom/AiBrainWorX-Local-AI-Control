param(
 [string]$Data=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/benchmarks/2026-10-25-coding-speed.json'),
 [string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'media')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$report=Get-Content -LiteralPath $Data -Raw -Encoding UTF8|ConvertFrom-Json
$new=@($report.trials|Where-Object {$_.cached_input_tokens -eq 0})
$cached=@($report.trials|Where-Object {$_.cached_input_tokens -gt 0})
if($new.Count -ne 4 -or $cached.Count -ne 2){throw 'Expected four new coding requests and two cached repeats.'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$culture=[Globalization.CultureInfo]::InvariantCulture
function N($Value,[int]$Places=1){([double]$Value).ToString(('F'+$Places),$culture)}
function Range($Rows,[string]$Field,[int]$Places=1){$m=$Rows|Measure-Object $Field -Minimum -Maximum;(N $m.Minimum $Places)+' - '+(N $m.Maximum $Places)}
function Text($Value,$X,$Y,$Size=24,$Color='#EEF8F3',$Weight='Regular'){
 $font=New-Object Drawing.Font('Segoe UI',$Size,[Drawing.FontStyle]::$Weight)
 $brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($Color))
 try{$script:g.DrawString([string]$Value,$font,$brush,$X,$Y)}finally{$font.Dispose();$brush.Dispose()}
}
function Rect($X,$Y,$W,$H,$Color){$brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($Color));try{$script:g.FillRectangle($brush,$X,$Y,$W,$H)}finally{$brush.Dispose()}}
function Line($X1,$Y1,$X2,$Y2,$Color='#244238',$Width=1){$pen=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml($Color),$Width);try{$script:g.DrawLine($pen,$X1,$Y1,$X2,$Y2)}finally{$pen.Dispose()}}
function Start-Graphic($Title){
 $script:bitmap=New-Object Drawing.Bitmap(1920,1080);$script:g=[Drawing.Graphics]::FromImage($script:bitmap)
 $script:g.SmoothingMode='AntiAlias';$script:g.TextRenderingHint='AntiAliasGridFit';$script:g.Clear([Drawing.ColorTranslator]::FromHtml('#080F12'))
 for($x=0;$x -lt 1920;$x+=80){Line $x 0 $x 1080 '#0C1B1C'}
 Text 'AiBrainWorX / MEASURED LOCAL AI' 80 42 25 '#BEFFCA' 'Bold'
 $logoPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'media/aibrainworx-wordmark-green.png'
 if(Test-Path -LiteralPath $logoPath){$logo=[Drawing.Image]::FromFile($logoPath);try{$script:g.DrawImage($logo,1500,35,340,88)}finally{$logo.Dispose()}}
 Text $Title 76 122 46 '#F0F8F3' 'Bold'
 Text 'ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF  |  IQ1_M' 82 226 23 '#BDCEC4'
 Text 'RTX 3060 12 GB  /  Ryzen 5 5500  /  32 GB RAM  /  Strata 0.1.48' 82 278 23 '#BDCEC4'
}
function Finish-Graphic($Name){
 try{$script:bitmap.Save((Join-Path $OutputDirectory $Name),[Drawing.Imaging.ImageFormat]::Png)}finally{$script:g.Dispose();$script:bitmap.Dispose()}
}
Start-Graphic 'QWEN CODER: COMPLETED SHORT TESTS'
try{
 for($i=0;$i -lt 3;$i++){$x=80+$i*595;Rect $x 366 560 344 '#12231E';Line $x 366 ($x+560) 366 '#71CDA2' 3}
 Text 'FOUR NEW CODING REQUESTS' 106 397 19 '#BDCEC4' 'Bold'
 Text (Range $new 'decode_tokens_per_second') 100 464 49 '#BEFFCA' 'Bold'
 Text 'decode tokens/s' 108 561 25
 Text '0 cached input tokens' 108 621 20 '#BDCEC4'
 Text 'Python / TypeScript / SQL' 108 666 19 '#BDCEC4'
 Text 'TWO IDENTICAL REPEATS' 701 397 19 '#BDCEC4' 'Bold'
 Text (Range $cached 'decode_tokens_per_second') 695 464 49 '#BEFFCA' 'Bold'
 Text 'decode tokens/s' 703 561 25
 Text '54 of 61 input tokens reused' 703 621 20 '#BDCEC4'
 Text 'Same 95-token reply each time' 703 666 19 '#BDCEC4'
 Text 'FIRST TOKEN / ENGINE' 1296 397 19 '#BDCEC4' 'Bold'
 Text ((Range $new 'first_engine_token_seconds' 2)+' s') 1290 464 41 '#BEFFCA' 'Bold'
 Text 'new coding requests' 1298 561 25
 Text ((Range $cached 'first_engine_token_seconds' 2)+' s on cached repeats') 1298 621 18 '#BDCEC4'
 Text 'Whole requests: 2.46 - 6.52 s' 1298 666 18 '#BDCEC4'
 Text 'All six replies completed normally / 95 - 136 output tokens each' 82 765 27 '#F0F8F3' 'Bold'
 Text 'Temperature 0  /  Reasoning off  /  Already-loaded, warmed engine' 82 827 25 '#BDCEC4'
 Text 'Zero prompt-cache reuse does not mean a cold model or expert cache.' 82 880 23 '#BDCEC4'
 Text 'Short samples; no sustained-speed or coding-quality guarantee.' 82 930 23 '#BDCEC4'
 Text 'Made by AiBrainWorX / October 25, 2026 / 08:29 Pacific test' 82 1007 22 '#BEFFCA'
 Finish-Graphic 'aibrainworx-coding-speed-20261025.png'
}catch{if($script:g){$script:g.Dispose();$script:bitmap.Dispose()};throw}
Start-Graphic 'FROM PROMPT TO REPLY: MEASURED LATENCY'
try{
 Rect 85 342 28 18 '#3E7667';Text 'Whole request (HTTP client)' 126 332 21 '#BDCEC4'
 Rect 785 342 28 18 '#BEFFCA';Text 'First token (engine)' 826 332 21 '#BDCEC4'
 Text 'TOTAL' 1570 382 18 '#BDCEC4' 'Bold';Text 'FIRST TOKEN' 1700 382 18 '#BDCEC4' 'Bold'
 for($tick=0;$tick -le 7;$tick++){$x=500+$tick*140;Line $x 423 $x 893 '#244238';Text ([string]$tick) ($x-8) 900 17 '#9EB8AC'}
 $names=@('Python merge','TypeScript groupBy','SQL query','Python clamp / new','Clamp / cached repeat 1','Clamp / cached repeat 2')
 for($i=0;$i -lt $report.trials.Count;$i++){
  $r=$report.trials[$i];$y=435+$i*76
  Text $names[$i] 82 ($y+4) 21 '#EEF8F3'
  Rect 500 $y ([single]($r.elapsed_seconds*140)) 35 '#3E7667'
  Rect 500 $y ([single]($r.first_engine_token_seconds*140)) 35 '#BEFFCA'
  Text ((N $r.elapsed_seconds 2)+' s') 1570 ($y+3) 21 '#EEF8F3' 'Bold'
  Text ((N $r.first_engine_token_seconds 2)+' s') 1720 ($y+3) 21 '#BEFFCA' 'Bold'
 }
 Text 'SECONDS / identical scale; independent engine and HTTP measurements' 500 942 19 '#BDCEC4'
 Text 'Temperature 0 / Reasoning off / Warm engine / Six completed short replies' 82 988 21 '#BDCEC4'
 Text 'AiBrainWorX / Oct 25, 2026' 1410 1030 17 '#BEFFCA'
 Finish-Graphic 'aibrainworx-coding-latency-20261025.png'
}catch{if($script:g){$script:g.Dispose();$script:bitmap.Dispose()};throw}
