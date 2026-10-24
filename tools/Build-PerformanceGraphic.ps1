param([string]$Output=(Join-Path (Split-Path $PSScriptRoot -Parent) 'media\aibrainworx-results.png'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$bitmap=New-Object Drawing.Bitmap(1920,1080);$g=[Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='AntiAliasGridFit';$g.Clear([Drawing.ColorTranslator]::FromHtml('#11151C'))
function Text($Value,$X,$Y,$Size=30,$Color='#F0F1F5'){
 $font=New-Object Drawing.Font('Segoe UI',$Size,[Drawing.FontStyle]::Regular);$brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($Color))
 try{$g.DrawString($Value,$font,$brush,$X,$Y)}finally{$font.Dispose();$brush.Dispose()}
}
try{
 Text 'AiBrainWorX / MEASURED LOCAL AI' 80 55 26 '#8AB4FF'
 Text 'WORKLOAD AND CACHE MATTER' 80 140 53
 Text 'RTX 3060 12 GB / Ryzen 5 5500 / 32 GB RAM' 83 240 28 '#ABB7C8'
 $values=@(@('FIRST REQUEST','17.4','0 cached input tokens','8.58 seconds total'),@('IDENTICAL REPEAT','30.9','38 cached input tokens','3.14 seconds total'),@('IDENTICAL REPEAT','36.7','38 cached input tokens','2.71 seconds total'))
 for($i=0;$i -lt 3;$i++){
  $x=80+$i*595;$brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#202630'));try{$g.FillRectangle($brush,$x,345,560,350)}finally{$brush.Dispose()}
  Text $values[$i][0] ($x+28) 373 20 '#ABB7C8';Text $values[$i][1] ($x+23) 420 82 '#8AB4FF'
  Text 'decode tokens/s' ($x+30) 548 24
  Text $values[$i][2] ($x+30) 603 19 '#ABB7C8';Text $values[$i][3] ($x+30) 641 19 '#ABB7C8'
 }
 Text 'Earlier different-request sample: 11.8 decode tokens/s.' 82 749 28
 Text 'Three identical short requests; each produced 93 tokens from 45 input tokens.' 82 813 25 '#ABB7C8'
 Text 'Temperature 0. Reasoning off. These are separate observations, not a sustained-speed guarantee.' 82 865 24 '#ABB7C8'
 Text 'Prompt processing, time to first token and complete task time matter too.' 82 917 24 '#ABB7C8'
 Text 'Made by AiBrainWorX / October 24, 2026 audit' 82 1010 22 '#8AB4FF'
 $bitmap.Save($Output,[Drawing.Imaging.ImageFormat]::Png)
}finally{$g.Dispose();$bitmap.Dispose()}
