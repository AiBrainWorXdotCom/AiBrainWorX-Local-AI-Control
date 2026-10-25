param([string]$Output=(Join-Path (Split-Path $PSScriptRoot -Parent) 'media\aibrainworx-results-20261025.png'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$bitmap=New-Object Drawing.Bitmap(1920,1080)
$g=[Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='AntiAliasGridFit'
$g.Clear([Drawing.ColorTranslator]::FromHtml('#080F12'))
function Write-GraphicText($Value,$X,$Y,$Size=30,$Color='#E9F7EE',$Weight='Regular'){
 $font=New-Object Drawing.Font('Segoe UI',$Size,[Drawing.FontStyle]::$Weight)
 $brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($Color))
 try{$g.DrawString($Value,$font,$brush,$X,$Y)}finally{$font.Dispose();$brush.Dispose()}
}
try {
 Write-GraphicText 'AiBrainWorX / MEASURED LOCAL AI' 80 48 27 '#BEFFCA' 'Bold'
 Write-GraphicText 'QWEN CODER: LATEST RESULTS' 78 126 48 '#F0F8F3' 'Bold'
 Write-GraphicText 'Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF  |  IQ1_M' 84 224 25 '#BDCEC4'
 Write-GraphicText 'RTX 3060 12 GB  /  Ryzen 5 5500  /  32 GB RAM  /  Strata' 84 280 24 '#BDCEC4'
 $cards=@(
  @('FIRST VARIED PROBES','13.7–17.3','After loading / three tasks','0 cached input tokens',54),
  @('COMPLETED CODE REVIEW','21.9','3,464 input / 733 output tokens','42.46 seconds total',82),
  @('LATER WARM PROBES','24.8–25.5','Warm engine / three tasks','0 cached input tokens',54)
 )
 for($i=0;$i -lt 3;$i++){
  $x=80+$i*595
  $brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#12231E'))
  $pen=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#3A6650'),2)
  try{$g.FillRectangle($brush,$x,366,560,343);$g.DrawRectangle($pen,$x,366,560,343)}finally{$brush.Dispose();$pen.Dispose()}
  Write-GraphicText $cards[$i][0] ($x+26) 393 19 '#BDCEC4' 'Bold'
  Write-GraphicText $cards[$i][1] ($x+22) 456 $cards[$i][4] '#BEFFCA' 'Bold'
  Write-GraphicText 'decode tokens/s' ($x+28) 574 24
  Write-GraphicText $cards[$i][2] ($x+28) 631 18 '#BDCEC4'
  Write-GraphicText $cards[$i][3] ($x+28) 669 18 '#BDCEC4'
 }
 Write-GraphicText 'Temperature 0  •  Reasoning off  •  Sequential local requests' 82 759 27
 Write-GraphicText 'Short probes capped at 192 output tokens; the code review completed normally.' 82 821 23 '#BDCEC4'
 Write-GraphicText 'Prompt-cache reuse, expert-cache warming and workload affect results.' 82 869 23 '#BDCEC4'
 Write-GraphicText 'Decode rates are not end-to-end speed or a sustained-performance guarantee.' 82 917 23 '#BDCEC4'
 Write-GraphicText 'Made by AiBrainWorX / October 25, 2026 review' 82 1007 22 '#BEFFCA'
 $bitmap.Save($Output,[Drawing.Imaging.ImageFormat]::Png)
} finally { $g.Dispose();$bitmap.Dispose() }
