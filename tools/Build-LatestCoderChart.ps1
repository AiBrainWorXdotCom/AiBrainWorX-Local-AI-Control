param([Parameter(Mandatory=$true)][string]$InputJson,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$data=Get-Content -LiteralPath $InputJson -Raw|ConvertFrom-Json
if(@($data.samples).Count -ne 6 -or $data.warmup.cachedInput -ne 0){throw 'Unexpected benchmark dataset.'}
$chart=[System.Windows.Forms.DataVisualization.Charting.Chart]::new()
$chart.Width=1600;$chart.Height=900;$chart.BackColor=[Drawing.ColorTranslator]::FromHtml('#0b1218')
$chart.Palette=[System.Windows.Forms.DataVisualization.Charting.ChartColorPalette]::None
$title=$chart.Titles.Add('LATEST QWEN CODER TEST  /  RTX 3060 12 GB')
$title.ForeColor=[Drawing.ColorTranslator]::FromHtml('#E8F7EE');$title.Font=[Drawing.Font]::new('Segoe UI',25,[Drawing.FontStyle]::Bold)
$sub=$chart.Titles.Add('Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF  |  IQ1_M  |  Windows  |  October 26, 2026')
$sub.ForeColor=[Drawing.ColorTranslator]::FromHtml('#A6C7B7');$sub.Font=[Drawing.Font]::new('Segoe UI',15)
$area=[System.Windows.Forms.DataVisualization.Charting.ChartArea]::new('results')
$area.BackColor=[Drawing.ColorTranslator]::FromHtml('#101d25')
$area.AxisY.Minimum=0;$area.AxisY.Maximum=55;$area.AxisY.Interval=10
$area.AxisY.Title='Decode tokens / second';$area.AxisY.TitleForeColor=[Drawing.Color]::White;$area.AxisY.TitleFont=[Drawing.Font]::new('Segoe UI',14)
foreach($axis in @($area.AxisX,$area.AxisY)){$axis.LabelStyle.ForeColor=[Drawing.ColorTranslator]::FromHtml('#C7DCD1');$axis.LabelStyle.Font=[Drawing.Font]::new('Segoe UI',12);$axis.LineColor=[Drawing.ColorTranslator]::FromHtml('#406353');$axis.MajorGrid.LineColor=[Drawing.ColorTranslator]::FromHtml('#263a39')}
$area.AxisX.MajorGrid.Enabled=$false;$chart.ChartAreas.Add($area)
$series=[System.Windows.Forms.DataVisualization.Charting.Series]::new('decode')
$series.ChartType=[System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Column
$series.IsValueShownAsLabel=$true;$series.LabelForeColor=[Drawing.Color]::White;$series.Font=[Drawing.Font]::new('Segoe UI',15,[Drawing.FontStyle]::Bold)
$values=@([pscustomobject]@{decodeTokensPerSecond=$data.warmup.decodeTokensPerSecond;lightMonitor=$false;finish=$data.warmup.finish})+@($data.samples)
for($i=0;$i -lt $values.Count;$i++){
 $p=[System.Windows.Forms.DataVisualization.Charting.DataPoint]::new();$p.SetValueY([double]$values[$i].decodeTokensPerSecond)
 $p.AxisLabel=if($i -eq 0){'Warmup' }elseif($i -eq 5){'5* / off'}else{('{0} / {1}' -f $i,$(if($values[$i].lightMonitor){'on'}else{'off'}))}
 $p.Label=('{0:0.0}{1}' -f $values[$i].decodeTokensPerSecond,$(if($values[$i].finish -eq 'length'){'*'}else{''}))
 $p.Color=[Drawing.ColorTranslator]::FromHtml($(if($i -eq 0){'#71858a'}elseif($values[$i].finish -eq 'length'){'#eeb768'}elseif($values[$i].lightMonitor){'#69edaa'}else{'#69c9da'}))
 [void]$series.Points.Add($p)
}
$chart.Series.Add($series)
foreach($line in @('Run 1-6: identical SHORT requests, 37 cached input tokens  |  on/off = light monitor  |  *Run 5 hit the output limit','Warmup: 0 cached input tokens  |  warm engine  |  temperature 0  |  reasoning off  |  max 256 output tokens','Individual observations, not a sustained speed guarantee or proof that monitoring increased speed.')){
 $t=$chart.Titles.Add($line);$t.Docking=[System.Windows.Forms.DataVisualization.Charting.Docking]::Bottom;$t.ForeColor=[Drawing.ColorTranslator]::FromHtml('#A6C7B7');$t.Font=[Drawing.Font]::new('Segoe UI',12)
}
$chart.SaveImage($Output,[System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]::Png)
$chart.Dispose()
