function Show-UserPlugins {
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='AiBrainWorX | User plugins';$dialog.Size=New-Object Drawing.Size(940,650);$dialog.StartPosition='CenterParent';$dialog.BackColor=$palette.Background;$dialog.ForeColor=$palette.Text;$dialog.Font=$form.Font
 [void](Ui-Label $dialog 'YOUR EXTENSIONS. YOUR WORKSPACE.' 24 22 870 32 17 $true)
 $intro=Ui-Label $dialog 'Plugins stay outside the launcher installation. App updates leave them intact. Changed code needs fresh approval.' 24 68 870 48 10;$intro.ForeColor=$palette.Muted
 $list=New-Object Windows.Forms.ListBox;$list.SetBounds(24,130,300,340);$list.DisplayMember='name';$list.BackColor=$palette.Card;$list.ForeColor=$palette.Text;$dialog.Controls.Add($list)
 $preview=Ui-Input $dialog 'No plugins installed. Put a reviewed plugin folder in your user plugin directory, then refresh. Voice/audio hooks are not implemented in API v1.' 344 130 550 340;$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical'
 $consent=Ui-Check $dialog 'I trust this local code to run with my account permissions (not sandboxed).' 24 488 870
 $dialog.Tag=@{List=$list;Preview=$preview;Consent=$consent;Settings=$settings;Config=$ConfigPath;PluginHome=(Join-Path $settings.StateRoot 'plugins')}
 $list.Add_SelectedIndexChanged({param($sender,$e);$m=$sender.SelectedItem;if($m){$v=$sender.FindForm().Tag;$v.Consent.Checked=$false;$v.Preview.Text=$m.name+"`r`n"+'State: '+$m.state+"`r`n"+'Plugin version: '+$m.version+' / Host API: '+$m.apiVersion+"`r`n`r`n"+'Declared capabilities: '+(@($m.capabilities)-join ', ')+"`r`n"+'Hooks: '+(@($m.hooks)-join ', ')+"`r`n`r`n"+'These are trusted local programs, not a security sandbox. Review source and dependencies before enabling. Incompatible plugins remain disabled and their files are preserved.'}})
 function Refresh-UserPluginList($d){$v=$d.Tag;$r=Invoke-AwxOperation $v.Settings $v.Config 'plugins';$v.List.Items.Clear();foreach($item in @($r.items)){if($item){[void]$v.List.Items.Add($item)}}}
 [void](Ui-Button $dialog 'Refresh' 24 540 130 {param($sender,$e);try{Refresh-UserPluginList $sender.FindForm()}catch{$sender.FindForm().Tag.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Open plugin folder' 166 540 180 {param($sender,$e);$v=$sender.FindForm().Tag;[void][IO.Directory]::CreateDirectory($v.PluginHome);Start-Process $v.PluginHome})
 [void](Ui-Button $dialog 'Enable reviewed' 358 540 180 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $v.Settings $v.Config 'plugin-approve' @{id=$m.id;fingerprint=$m.fingerprint;enabled=$true;acceptLocalCodeRisk=$v.Consent.Checked});Refresh-UserPluginList $d}catch{$v.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Disable' 550 540 130 {param($sender,$e);$d=$sender.FindForm();$v=$d.Tag;$m=$v.List.SelectedItem;if(-not $m){return};try{[void](Invoke-AwxOperation $v.Settings $v.Config 'plugin-approve' @{id=$m.id;fingerprint=$m.fingerprint;enabled=$false});Refresh-UserPluginList $d}catch{$v.Preview.Text=$_.Exception.Message}})
 [void](Ui-Button $dialog 'Close' 714 540 180 {param($sender,$e);$sender.FindForm().Close()})
 try{Refresh-UserPluginList $dialog}catch{$preview.Text=$_.Exception.Message}
 [void]$dialog.ShowDialog($form);$dialog.Dispose()
}
