$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'app/Skills.ps1')
Add-Type -AssemblyName System.Windows.Forms
$entries=@(Get-AwxSkillCatalog)
if($entries.Count -ne 12){throw 'The workflow catalog must expose 12 separate entries.'}
$list=New-Object Windows.Forms.ListBox;$list.DisplayMember='name'
try{
 foreach($entry in $entries){[void]$list.Items.Add($entry)}
 $bundled=0
 for($index=0;$index -lt $list.Items.Count;$index++){
  $list.SelectedIndex=$index;$selected=$list.SelectedItem
  if($selected -is [array] -or -not ($selected.name -is [string])){throw 'A list selection must identify one workflow.'}
  if($selected.path){
   if(-not ($selected.path -is [string])){throw 'A bundled workflow path must be scalar.'}
   $file=Join-Path (Join-Path $root 'skills') $selected.path
   $text=Get-Content -LiteralPath $file -Raw -Encoding UTF8
   if(-not $text.StartsWith('---')){throw 'A bundled guide has no skill frontmatter.'};$bundled++
  }elseif(-not $selected.url.StartsWith('https://github.com/')){throw 'Upstream references need a public GitHub source.'}
 }
 if($bundled -ne 8){throw 'Expected eight original bundled guides.'}
}finally{$list.Dispose()}
Write-Output 'Workflow catalog passed: all 12 entries select individually; eight local skill paths read successfully.'
