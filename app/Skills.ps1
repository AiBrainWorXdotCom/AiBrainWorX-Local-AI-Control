function Show-WorkflowLibrary {
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='AiBrainWorX | Skills and profile templates';$dialog.Size=New-Object Drawing.Size(960,640);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 [void](Ui-Label $dialog 'Skills guide the coding client; templates configure a workspace.' 20 20 900 36 16 $true)
 $note=Ui-Label $dialog 'Choose a template in Profiles + prompts. Bundled guides are original MIT instructions. Upstream references are not automatically installed or executed.' 20 65 900 46 10;$note.ForeColor=$palette.Muted
 $items=Get-AwxSkillCatalog
 $list=New-Object Windows.Forms.ListBox;$list.SetBounds(20,127,330,380);$list.DisplayMember='name';$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text;foreach($entry in $items){[void]$list.Items.Add($entry)};$dialog.Controls.Add($list)
 $preview=Ui-Input $dialog 'Select a bundled guide or upstream reference.' 370 127 550 380;$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical'
 $dialog.Tag=@{List=$list;Preview=$preview}
 $list.Add_SelectedIndexChanged({param($sender,$e);$m=$sender.SelectedItem;if($m){$u=$sender.FindForm().Tag;$u.Preview.Text=$m.name+"`r`n"+$m.kind+' / '+$m.license+"`r`n`r`n"+$m.review;if($m.path){$u.Preview.Text+="`r`n`r`n"+(Get-Content -LiteralPath (Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills') $m.path) -Raw -Encoding UTF8).Replace("`r`n","`n").Replace("`n","`r`n")}elseif($m.revision){$u.Preview.Text+="`r`nReviewed revision: "+$m.revision}}})
 [void](Ui-Button $dialog 'Open upstream project' 20 539 260 {param($sender,$e);$m=$sender.FindForm().Tag.List.SelectedItem;if($m -and $m.url -and $m.url.StartsWith('https://github.com/')){Start-Process $m.url}})
 [void](Ui-Button $dialog 'Close' 760 539 160 {param($sender,$e);$sender.FindForm().Close()})
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
}

function Get-AwxSkillCatalog {
 $catalog=Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'skills/catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($entry in $catalog){Write-Output $entry}
}
