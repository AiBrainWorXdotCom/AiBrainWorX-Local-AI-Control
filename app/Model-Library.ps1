function Show-ModelLibrary {
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='AiBrainWorX | Local model library';$dialog.Size=New-Object Drawing.Size(980,730);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 $entries=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'model-suggestions.json') -Raw | ConvertFrom-Json)
 [void](Ui-Label $dialog 'Ideas for chat, stories, learning and puzzles' 20 18 900 32 17 $true)
 $note=Ui-Label $dialog 'MIT / Apache-2.0 source metadata checked. Check the exact quantization and base-model terms before downloading.' 20 57 920 40 9;$note.ForeColor=$palette.Muted
 $details=@{};foreach($card in @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'model-details.json') -Raw -Encoding UTF8 | ConvertFrom-Json)){$details[$card.id]=$card}
 $list=New-Object Windows.Forms.ListView;$list.View='Details';$list.FullRowSelect=$true;$list.MultiSelect=$false;$list.SetBounds(20,110,920,300);$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text
 [void]$list.Columns.Add('Original model / creator',355);[void]$list.Columns.Add('Try it for',190);[void]$list.Columns.Add('Starting hardware tier',235);[void]$list.Columns.Add('License',110)
 foreach($entry in $entries){$item=New-Object Windows.Forms.ListViewItem($entry.id);[void]$item.SubItems.Add($entry.use);[void]$item.SubItems.Add($entry.hardwareHint);[void]$item.SubItems.Add($entry.license);$item.Tag=$details[$entry.id];[void]$list.Items.Add($item)};$dialog.Controls.Add($list)
 $preview=Ui-Input $dialog 'Select a model to read its summary, context, license and local-use notes.' 20 424 920 140;$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical';$list.Tag=$preview
 $list.Add_SelectedIndexChanged({param($sender,$e);if($sender.SelectedItems.Count){$m=$sender.SelectedItems[0].Tag;$sender.Tag.Text=$m.summary+"`r`n`r`nCreator: "+$m.creator+' | License: '+$m.license+' | Context: '+$m.context+"`r`n"+$m.localNote+"`r`n"+$m.tested}})
 $hint=Ui-Label $dialog 'Hardware tiers are suggestions, not fit guarantees. Models stay credited to their creators. Choose and load a compatible quantization in your backend.' 20 577 920 40 9;$hint.ForeColor=$palette.Muted
 $dialog.Tag=$list
 [void](Ui-Button $dialog 'Read AiBrainWorX model guide' 20 632 285 {param($sender,$e);$l=$sender.FindForm().Tag;if($l.SelectedItems.Count){$url=$l.SelectedItems[0].Tag.detailsUrl;if($url.StartsWith('https://aibrainworx.com/model-library/')){Start-Process $url}}})
 [void](Ui-Button $dialog 'Original source card' 320 632 240 {param($sender,$e);$l=$sender.FindForm().Tag;if($l.SelectedItems.Count){$url=$l.SelectedItems[0].Tag.source;if($url.StartsWith('https://huggingface.co/')){Start-Process $url}}})
 [void](Ui-Button $dialog 'Close' 780 632 160 {param($sender,$e);$sender.FindForm().Close()})
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
}
