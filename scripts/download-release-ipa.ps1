param([Parameter(Mandatory=$true)][string]$Repo,[Parameter(Mandatory=$true)][string]$Version,[string]$OutputDir="release/ios",[string]$CommitSha="")
$ErrorActionPreference='Stop';$headers=@{'Accept'='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
if($env:GITHUB_TOKEN){$headers['Authorization']="Bearer $env:GITHUB_TOKEN"}
if($CommitSha){$runs=Invoke-RestMethod -Headers $headers "https://api.github.com/repos/$Repo/actions/runs?head_sha=$CommitSha";if(-not $runs.workflow_runs){throw "No workflow run for commit $CommitSha"};$run=$runs.workflow_runs[0];if($run.status-ne'completed'-or$run.conclusion-ne'success'){throw "Workflow is $($run.status)/$($run.conclusion): $($run.html_url)"}}
$release=Invoke-RestMethod -Headers $headers "https://api.github.com/repos/$Repo/releases/tags/ios-v$Version";$name="DroidBox-$Version-unsigned.ipa";$asset=$release.assets|Where-Object name -eq $name;if(-not $asset){throw "Release asset $name not found"}
New-Item -ItemType Directory -Force $OutputDir|Out-Null;$assetHeaders=$headers.Clone();$assetHeaders['Accept']='application/octet-stream';$versioned=Join-Path $OutputDir $name
Invoke-WebRequest -Headers $assetHeaders -Uri "https://api.github.com/repos/$Repo/releases/assets/$($asset.id)" -OutFile $versioned;Copy-Item $versioned (Join-Path $OutputDir 'DroidBox-unsigned.ipa') -Force
Get-FileHash $versioned -Algorithm SHA256|Format-List Path,Hash

