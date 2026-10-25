function Fill-AwxLibrary($Dialog){
 $u=$Dialog.Tag;$u.List.Items.Clear();$u.Preview.Text='Select an entry to read its compatibility and license notes.'
 $entries=if($u.Mode.Text -eq 'Datasets'){$u.Datasets}else{$u.Models}
 $cat=@('all','text','tts','vision','asr','embeddings','edge','research','video')[$u.Category.SelectedIndex];$query=$u.Search.Text.Trim()
 foreach($entry in $entries){
  if($cat -ne 'all' -and $(if($cat -eq 'edge'){-not $entry.edgeCandidate}else{$entry.category -ne $cat})){continue}
  $searchText=($entry|ConvertTo-Json -Depth 8 -Compress)
  if($query -and $searchText.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
  $item=New-Object Windows.Forms.ListViewItem($entry.id)
  [void]$item.SubItems.Add($entry.category)
  [void]$item.SubItems.Add($(if($u.Mode.Text -eq 'Datasets'){$entry.compatibility}else{$entry.integrationStatus}))
  [void]$item.SubItems.Add($entry.license);$item.Tag=$entry;[void]$u.List.Items.Add($item)
 }
 $u.Count.Text=[string]$u.List.Items.Count+' entries / metadata only'
}

function Show-ModelLibrary([string]$Initial='Models') {
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='AiBrainWorX | Models and datasets';$dialog.Size=New-Object Drawing.Size(980,730);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 $models=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'model-details.json') -Raw -Encoding UTF8|ConvertFrom-Json)
 $datasets=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'dataset-suggestions.json') -Raw -Encoding UTF8|ConvertFrom-Json)
 [void](Ui-Label $dialog 'Find the right model, runtime and dataset' 20 18 900 32 17 $true)
 $note=Ui-Label $dialog 'Text, voice, vision and tiny edge candidates. Original creators and licenses stay visible. No automatic downloads.' 20 57 920 40 9;$note.ForeColor=$palette.Muted
 $mode=Ui-Combo $dialog @('Models','Datasets') 20 107 170
 $category=Ui-Combo $dialog @('All categories','Text','Voice / TTS','Vision','Speech recognition','Embeddings','Tiny edge candidates','Research','Video / Avatar') 205 107 270
 $search=Ui-Input $dialog '' 490 107 450
 $list=New-Object Windows.Forms.ListView;$list.View='Details';$list.FullRowSelect=$true;$list.MultiSelect=$false;$list.SetBounds(20,154,920,250);$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text
 [void]$list.Columns.Add('Original reference',335);[void]$list.Columns.Add('Task',100);[void]$list.Columns.Add('Integration / preparation',355);[void]$list.Columns.Add('License',110);$dialog.Controls.Add($list)
 $preview=Ui-Input $dialog '' 20 418 920 145;$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical'
 $count=Ui-Label $dialog '' 20 574 920 24 9;$count.ForeColor=$palette.Cyan
 $hint=Ui-Label $dialog 'Catalogued does not mean runnable in Chat or tested on Android. Training matches describe workflows; local data, weights and rights still need validation.' 20 601 920 26 8;$hint.ForeColor=$palette.Muted
 $dialog.Tag=@{Mode=$mode;Category=$category;Search=$search;List=$list;Preview=$preview;Models=$models;Datasets=$datasets;Count=$count}
 foreach($control in @($mode,$category)){$control.Add_SelectedIndexChanged({param($sender,$e);Fill-AwxLibrary $sender.FindForm()})}
 $search.Add_TextChanged({param($sender,$e);Fill-AwxLibrary $sender.FindForm()})
 $list.Add_SelectedIndexChanged({param($sender,$e);if($sender.SelectedItems.Count){$u=$sender.FindForm().Tag;$m=$sender.SelectedItems[0].Tag;$u.Preview.Text=$m.summary+"`r`n`r`nLicense: "+$m.license+$(if($u.Mode.Text -eq 'Datasets'){"`r`nFormat: "+$m.format+"`r`nWorkflow: "+$m.workflow+"`r`n"+$m.requirements}else{"`r`nCreator: "+$m.creator+' | Context: '+$m.context+"`r`nIntegration: "+$m.integrationStatus+"`r`nTraining: "+$m.trainingWorkflow+"`r`n"+$m.localNote})+"`r`n"+$m.tested}})
 [void](Ui-Button $dialog 'Read AiBrainWorX guide' 20 644 260 {param($sender,$e);$u=$sender.FindForm().Tag;if($u.List.SelectedItems.Count){$url=$u.List.SelectedItems[0].Tag.detailsUrl;if($url.StartsWith('https://aibrainworx.com/')){Start-Process $url}}})
 [void](Ui-Button $dialog 'Original source' 295 644 205 {param($sender,$e);$u=$sender.FindForm().Tag;if($u.List.SelectedItems.Count){$url=$u.List.SelectedItems[0].Tag.source;if($url.StartsWith('https://huggingface.co/') -or $url.StartsWith('https://github.com/') -or $url.StartsWith('https://keithito.com/LJ-Speech-Dataset/')){Start-Process $url}}})
 [void](Ui-Button $dialog 'Matching datasets' 515 644 220 {param($sender,$e);$u=$sender.FindForm().Tag;if($u.Mode.Text -eq 'Models' -and $u.List.SelectedItems.Count){$c=$u.List.SelectedItems[0].Tag.category;$u.Mode.SelectedIndex=1;$u.Category.SelectedIndex=[Array]::IndexOf(@('all','text','tts','vision','asr','embeddings','edge','research','video'),$c);$u.Search.Clear();Fill-AwxLibrary $sender.FindForm()}})
 [void](Ui-Button $dialog 'Close' 780 644 160 {param($sender,$e);$sender.FindForm().Close()})
 if($Initial -eq 'Datasets'){$mode.SelectedIndex=1};if($Initial -eq 'Video'){$category.SelectedIndex=8};Fill-AwxLibrary $dialog
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
}
