# Explicit local-file playback, inside Chat. No media links from model text run.
$script:videoHost=$null
$videoPanel=Ui-Box $chat 354 111 444 365;$videoPanel.Visible=$false
$videoCaption=Ui-Label $videoPanel 'LOCAL VIDEO / NO UPLOAD' 12 8 420 24 8 $true
$videoNote=Ui-Label $videoPanel 'Choose a completed local MP4. The video generator runs separately.' 12 44 420 70 10
function Close-ChatVideo {
 if($script:videoHost){try{$script:videoHost.Player.controls.stop();$script:videoHost.Dispose()}catch{};$script:videoHost=$null}
 $videoPanel.Visible=$false;$chatOutput.SetBounds(32,111,766,365)
}
function Open-ChatVideo([string]$Path) {
 try{
  if(-not [IO.Path]::IsPathRooted($Path) -or -not [IO.File]::Exists($Path) -or [IO.Path]::GetExtension($Path).ToLowerInvariant() -notin @('.mp4','.m4v','.wmv','.avi')){throw 'Choose an existing local MP4, M4V, WMV or AVI file.'}
  if(-not [Type]::GetTypeFromProgID('WMPlayer.OCX')){throw 'In-Chat playback needs the optional Windows Media Player legacy component. Enable it in Windows Optional features, then reopen the launcher.'}
  if(-not ('AwxVideoHost' -as [type])){
   Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Windows.Forms;
public sealed class AwxVideoHost : AxHost {
 public AwxVideoHost() : base("6BF52A52-394A-11D3-B153-00C04F79FAA6") {}
 public object Player { get { return GetOcx(); } }
}
'@
  }
  if(-not $script:videoHost){
   $script:videoHost=New-Object AwxVideoHost
   ([ComponentModel.ISupportInitialize]$script:videoHost).BeginInit()
   $script:videoHost.SetBounds(0,36,444,329);$videoPanel.Controls.Add($script:videoHost)
   ([ComponentModel.ISupportInitialize]$script:videoHost).EndInit()
  }
  $chatOutput.SetBounds(32,111,310,365);$videoPanel.Visible=$true;$videoPanel.BringToFront();$videoNote.Visible=$false
  $player=$script:videoHost.Player;$player.settings.autoStart=$false;$player.enableContextMenu=$false;$player.uiMode='full';$player.stretchToFit=$true;$player.URL=[IO.Path]::GetFullPath($Path)
  $videoCaption.Text=[IO.Path]::GetFileName($Path)
  $feedback.Text='Local video loaded in Chat. Use its playback controls; no media was sent to the model.'
 }catch{Close-ChatVideo;$feedback.Text=$_.Exception.Message}
}
[void](Ui-Button $chat 'Open video' 602 25 126 {
 $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='Local video (*.mp4;*.m4v;*.wmv;*.avi)|*.mp4;*.m4v;*.wmv;*.avi';$dialog.CheckFileExists=$true
 if($dialog.ShowDialog($form) -eq 'OK'){Open-ChatVideo $dialog.FileName};$dialog.Dispose()
})
[void](Ui-Button $chat 'Hide' 738 25 60 {Close-ChatVideo})
