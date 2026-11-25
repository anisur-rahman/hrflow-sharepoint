#Requires -Version 7.4
param([Parameter(Mandatory)][guid]$ClientId,[Parameter(Mandatory)][string]$SiteUrl,[switch]$Apply,[switch]$UpdatePages,[string[]]$Only,[switch]$SetBranding,[switch]$SeedDemo,[switch]$SetHomepage)
$ErrorActionPreference='Stop'
$config=Get-Content "$PSScriptRoot/site-config.json" -Raw | ConvertFrom-Json
if(!$Apply){ $config | ConvertTo-Json -Depth 10; Write-Host 'Preview only. Use -Apply to provision.'; return }
Import-Module PnP.PowerShell
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId
$web=Get-PnPWeb -Includes ServerRelativeUrl
$base=$web.ServerRelativeUrl.TrimEnd('/')
foreach($lib in $config.libraries){
 if(!(Get-PnPList -Identity $lib -ErrorAction SilentlyContinue)){New-PnPList -Title $lib -Template DocumentLibrary -EnableVersioning | Out-Null}
}
foreach($list in $config.lists){
 if(!(Get-PnPList -Identity $list.name -ErrorAction SilentlyContinue)){New-PnPList -Title $list.name -Template GenericList | Out-Null}
 foreach($f in $list.fields){if(!(Get-PnPField -List $list.name -Identity $f.name -ErrorAction SilentlyContinue)){
 $argsField=@{List=$list.name;DisplayName=$f.name;InternalName=$f.name;Type=$f.type;AddToDefaultView=$true}
 if($f.choices){$argsField.Choices=[string[]]$f.choices}; Add-PnPField @argsField | Out-Null
 }
 # Form settings: label, required, date only, default value, hidden on the new-item form.
 $field=Get-PnPField -List $list.name -Identity $f.name; $x=[xml]$field.SchemaXml; $before=$x.OuterXml
 if($f.label){$x.Field.SetAttribute('DisplayName',$f.label)}
 if($f.required){$x.Field.SetAttribute('Required','TRUE')}
 if($f.type -eq 'DateTime'){$x.Field.SetAttribute('Format','DateOnly')}
 if($f.hideOnNew){$x.Field.SetAttribute('ShowInNewForm','FALSE')}
 if($f.default -and !$x.Field.SelectSingleNode('Default')){$n=$x.CreateElement('Default'); $n.InnerText=$f.default; $x.Field.AppendChild($n) | Out-Null}
 if($x.OuterXml -ne $before){Set-PnPField -List $list.name -Identity $f.name -Values @{SchemaXml=$x.OuterXml} | Out-Null}
 }
 if($list.titleLabel){Set-PnPField -List $list.name -Identity 'Title' -Values @{Title=$list.titleLabel} | Out-Null}
}
if($SeedDemo){
 $demo=Get-Content "$PSScriptRoot/demo-content.json" -Raw | ConvertFrom-Json
 foreach($set in $demo.items.PSObject.Properties){
  if((Get-PnPList -Identity $set.Name).ItemCount -gt 0){Write-Host "Skipping items for $($set.Name): not empty"; continue}
  foreach($item in $set.Value){$v=@{}; $item.PSObject.Properties | ForEach-Object { $v[$_.Name]=$_.Value }; Add-PnPListItem -List $set.Name -Values $v | Out-Null}
  Write-Host "Added $(@($set.Value).Count) items to $($set.Name)"
 }
 foreach($dir in Get-ChildItem "$PSScriptRoot/documents" -Directory){
  $folder=(Get-PnPList -Identity $dir.Name -Includes RootFolder).RootFolder.ServerRelativeUrl
  $existing=@(Get-PnPListItem -List $dir.Name | ForEach-Object { $_['FileLeafRef'] })
  foreach($file in Get-ChildItem $dir.FullName -Filter *.docx){
   if($file.Name -in $existing){Write-Host "Skipping existing $($file.Name)"; continue}
   Add-PnPFile -Path $file.FullName -Folder $folder | Out-Null; Write-Host "Uploaded $($dir.Name)/$($file.Name)"
  }
 }
 foreach($post in $demo.news){
  $postName="HRFlow-News-$($post.slug).aspx"
  if(Get-PnPPage -Identity $postName -ErrorAction SilentlyContinue){Write-Host "Skipping existing $postName"; continue}
  Add-PnPPage -Name $postName -Title $post.title -LayoutType Article -PromoteAs NewsArticle | Out-Null
  Add-PnPPageSection -Page $postName -SectionTemplate OneColumn -Order 1 | Out-Null
  $postHtml=($post.body | ForEach-Object { '<p>'+[System.Net.WebUtility]::HtmlEncode($_)+'</p>' }) -join ''
  Add-PnPPageTextPart -Page $postName -Text $postHtml -Section 1 -Column 1 | Out-Null
  Set-PnPPage -Identity $postName -HeaderLayoutType ColorBlock -Publish | Out-Null
  Write-Host "Posted $postName"
 }
}
$site=Get-PnPSite -Includes Id
$web=Get-PnPWeb -Includes ServerRelativeUrl,Id
$origin=([uri]$SiteUrl).GetLeftPart('Authority')
$quickLinksId='c70391ea-0b10-4ee9-b2b4-006d3fcad0cd'; $listPartId='f92bf067-bc19-489e-a556-7fe95f508720'
function ConvertTo-Html($text){[System.Net.WebUtility]::HtmlEncode($text)}
# Quick Links codes: buttonTreatment 2=outline 3=filled; iconPositionType 2=left 3=top.
function ConvertTo-QuickLinks($links,$title='',$layout='Button',$treatment=2,$iconPosition=2){
 $items=@(); $texts=@{title=$title}; $urls=@{baseUrl="$origin$base"}; $i=0
 foreach($l in $links){
  $items+=@{id=$i+1;sourceItem=@{itemType=2;fileExtension='';progId=''};thumbnailType=2;description='';altText='';fabricReactIcon=@{iconName=$l.icon}}
  $texts["items[$i].title"]=$l.title; $urls["items[$i].sourceItem.url"]=$l.url; $i++
 }
 @{webPartData=@{id=$quickLinksId;title='Quick links';dataVersion='2.2'
  properties=@{items=$items;isMigrated=$true;layoutId=$layout;shouldShowThumbnail=$true;hideWebPartWhenEmpty=$true;dataProviderId='QuickLinks';webId="$($web.Id)";siteId="$($site.Id)"
   buttonLayoutOptions=@{showDescription=$false;buttonTreatment=$treatment;iconPositionType=$iconPosition;textAlignmentVertical=2;textAlignmentHorizontal=2;linesOfText=2}
   listLayoutOptions=@{showDescription=$false;showIcon=$true}}
  serverProcessedContent=@{htmlStrings=@{};searchablePlainTexts=$texts;imageSources=@{};links=$urls}}} | ConvertTo-Json -Depth 10
}
function Get-PageLink($slug,$label){
 $t=$config.pages | Where-Object slug -eq $slug
 @{title=$label ? $label : $t.title;icon=$t.icon;url="$origin$base/SitePages/HRFlow-$slug.aspx"}
}
function Add-HomeContent($name,$p){
 $h=$p.home
 Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order 1 -ZoneEmphasis 3 | Out-Null
 Add-PnPPageTextPart -Page $name -Text "<p>$(ConvertTo-Html $h.tagline)</p>" -Section 1 -Column 1 | Out-Null
 Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order 2 -ZoneEmphasis 1 | Out-Null
 Add-PnPPageTextPart -Page $name -Text "<p>$(ConvertTo-Html $h.eyebrow)</p><h2>$(ConvertTo-Html $p.title)</h2><p>$(ConvertTo-Html $p.body)</p>" -Section 2 -Column 1 | Out-Null
 Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order 3 | Out-Null
 $links=@($h.departments | ForEach-Object { Get-PageLink $_.slug $_.label })
 Add-PnPPageWebPart -Page $name -DefaultWebPartType QuickLinks -Section 3 -Column 1 -WebPartProperties (ConvertTo-QuickLinks $links $h.departmentsTitle 'Button' 3 3) | Out-Null
 Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order 4 | Out-Null
 $links=@($h.actions | ForEach-Object { Get-PageLink $_.slug $_.label })
 Add-PnPPageWebPart -Page $name -DefaultWebPartType QuickLinks -Section 4 -Column 1 -WebPartProperties (ConvertTo-QuickLinks $links 'Quick actions' 'Button' 2 3) | Out-Null
 Add-PnPPageSection -Page $name -SectionTemplate TwoColumn -Order 5 | Out-Null
 $links=@($h.documents | ForEach-Object { $l=Get-PnPList -Identity $_.library -Includes RootFolder; @{title=$_.label;icon='TextDocument';url="$origin$($l.RootFolder.ServerRelativeUrl)$($_.file ? "/$($_.file)?web=1" : '')"} })
 Add-PnPPageWebPart -Page $name -DefaultWebPartType QuickLinks -Section 5 -Column 1 -WebPartProperties (ConvertTo-QuickLinks $links 'Important documents' 'List') | Out-Null
 $news=($h.announcements | ForEach-Object { "<p><strong>$(ConvertTo-Html $_.label)</strong></p><p><a href=`"$base/SitePages/HRFlow-News-$($_.news).aspx`">$(ConvertTo-Html $_.title)</a></p>" }) -join ''
 Add-PnPPageTextPart -Page $name -Text "<h3>Latest announcements</h3>$news" -Section 5 -Column 2 | Out-Null
}
foreach($p in $config.pages){
 if($Only -and $p.slug -notin $Only){continue}
 $name="HRFlow-$($p.slug).aspx"
 $page=Get-PnPPage -Identity $name -ErrorAction SilentlyContinue
 if($page -and !$UpdatePages){Write-Host "Skipping existing $name (use -UpdatePages to rebuild it)"; continue}
 if($page){
  # Rebuild only pages made of parts this script creates, so browser-added web parts are never lost.
  $text=@($page.Controls | Where-Object { $_.GetType().Name -eq 'PageText' })
  $other=@($page.Controls | Where-Object { $_.GetType().Name -ne 'PageText' -and $_.WebPartId -notin $quickLinksId,$listPartId })
  if($text.Count -gt ($p.home ? 3 : 1) -or $other.Count){Write-Warning "Skipping ${name}: it contains web parts added outside this script"; continue}
 }
 $html='<p>'+[System.Net.WebUtility]::HtmlEncode($p.body)+'</p>'
 foreach($f in $p.faq){$html+='<h3>'+[System.Net.WebUtility]::HtmlEncode($f.q)+'</h3><p>'+[System.Net.WebUtility]::HtmlEncode($f.a)+'</p>'}
 foreach($c in $p.content){$html+='<h3>'+(ConvertTo-Html $c.heading)+'</h3><ul>'+(($c.bullets | ForEach-Object { "<li>$(ConvertTo-Html $_)</li>" }) -join '')+'</ul>'}
 $links=@(); $embeds=@()
 foreach($link in $p.links){$links+=Get-PageLink $link}
 foreach($resource in $p.resources){
  $l=Get-PnPList -Identity $resource -Includes RootFolder
  $embeds+=$l
 }
 if($page){$page.ClearPage(); $page.Save($name) | Out-Null}
 else{Add-PnPPage -Name $name -Title $p.title -LayoutType Article | Out-Null}
 if($p.home){
  Add-HomeContent $name $p
  Set-PnPPage -Identity $name -Title $p.title -LayoutType Home -Publish | Out-Null
  Write-Host "$($page ? 'Updated' : 'Created') $name"; continue
 }
 $order=1
 Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order $order | Out-Null
 Add-PnPPageTextPart -Page $name -Text $html -Section $order -Column 1 | Out-Null
 if($p.form){
  $order++; $formUrl=(Get-PnPList -Identity $p.form.list -Includes RootFolder).RootFolder.ServerRelativeUrl+'/NewForm.aspx?Source='+[uri]::EscapeDataString("$origin$base/SitePages/$name")
  Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order $order | Out-Null
  Add-PnPPageWebPart -Page $name -DefaultWebPartType QuickLinks -Section $order -Column 1 -WebPartProperties (ConvertTo-QuickLinks @(@{title=$p.form.label;icon='Edit';url="$origin$formUrl"}) '' 'Button' 3 2) | Out-Null
 }
 if($links.Count){
  $order++
  Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order $order -ZoneEmphasis 1 | Out-Null
  Add-PnPPageWebPart -Page $name -DefaultWebPartType QuickLinks -Section $order -Column 1 -WebPartProperties (ConvertTo-QuickLinks $links) | Out-Null
 }
 foreach($l in $embeds){
  $order++; $folder=$l.RootFolder.ServerRelativeUrl
  Add-PnPPageSection -Page $name -SectionTemplate OneColumn -Order $order | Out-Null
  $props=@{isDocumentLibrary=($l.BaseTemplate -eq 101);selectedListId="$($l.Id)";listTitle=$l.Title;selectedListUrl=$folder;webRelativeListUrl=$folder.Substring($base.Length);hideCommandBar=$false} | ConvertTo-Json
  Add-PnPPageWebPart -Page $name -DefaultWebPartType List -Section $order -Column 1 -WebPartProperties $props | Out-Null
 }
 Set-PnPPage -Identity $name -Title $p.title -HeaderLayoutType ColorBlock -Publish | Out-Null
 Write-Host "$($page ? 'Updated' : 'Created') $name"
}
if(!$Only){
 # Both sets are filled because the header of a communication site can read from either one.
 foreach($location in 'TopNavigationBar','QuickLaunch'){
  $nav=Get-PnPNavigationNode -Location $location
  $topPages=@($config.pages | Where-Object navigation); [array]::Reverse($topPages)
  foreach($p in $topPages){
   $url="$base/SitePages/HRFlow-$($p.slug).aspx"
   if(!($nav | Where-Object Url -eq $url)){Add-PnPNavigationNode -Location $location -Title $p.slug.Replace('-',' ') -Url $url -First | Out-Null; Write-Host "Added $location item $($p.slug)"}
  }
  # Drop menu items for pages whose "navigation" was switched off in the config.
  if($UpdatePages){
   $off=@($config.pages | Where-Object { !$_.navigation } | ForEach-Object { "$base/SitePages/HRFlow-$($_.slug).aspx" })
   $nav | Where-Object { $_.Url -in $off } | ForEach-Object { Remove-PnPNavigationNode -Identity $_.Id -Force }
  }
  $nav=Get-PnPNavigationNode -Location $location
  # Remove submenu items for pages that have no "parent" any more.
  if($UpdatePages){
   $flat=@($config.pages | Where-Object { !$_.parent } | ForEach-Object { "$base/SitePages/HRFlow-$($_.slug).aspx" })
   foreach($top in $nav){(Get-PnPNavigationNode -Id $top.Id).Children | Where-Object { $_.Url -in $flat } | ForEach-Object { Remove-PnPNavigationNode -Identity $_.Id -Force }}
  }
  # Pages with a "parent" go underneath that page's menu item.
  foreach($group in $config.pages | Where-Object parent | Group-Object parent){
   $top=$nav | Where-Object Url -eq "$base/SitePages/HRFlow-$($group.Name).aspx" | Select-Object -First 1
   if(!$top){Write-Warning "No menu item for parent '$($group.Name)'"; continue}
   $children=@((Get-PnPNavigationNode -Id $top.Id).Children)
   foreach($p in $group.Group){
    $url="$base/SitePages/HRFlow-$($p.slug).aspx"
    if(!($children | Where-Object Url -eq $url)){Add-PnPNavigationNode -Location $location -Title $p.title -Url $url -Parent $top.Id | Out-Null; Write-Host "Added $location item $($group.Name) > $($p.title)"}
   }
  }
 }
}
if($SetBranding){
 $web.Lists.EnsureSiteAssetsLibrary() | Out-Null; Invoke-PnPQuery
 Add-PnPFile -Path "$PSScriptRoot/$($config.site.logo)" -Folder 'SiteAssets' | Out-Null
 # Applies the palette to this site only; the tenant theme gallery is not changed.
 [string]$themeJson=@{palette=$config.site.theme.palette;isInverted=$false} | ConvertTo-Json -Compress
 $theme=@{name=[string]$config.site.theme.name;themeJson=$themeJson}
 Invoke-PnPSPRestMethod -Method Post -Url '/_api/ThemeManager/ApplyTheme' -Content $theme | Out-Null
 Set-PnPWeb -Title $config.site.title | Out-Null
 Set-PnPWebHeader -HeaderLayout Standard -HeaderEmphasis Strong -SiteLogoUrl "$base/SiteAssets/$($config.site.logo)"
 Set-PnPFooter -Enabled -Layout Simple -BackgroundTheme Strong -Title $config.site.footer
 Write-Host 'Updated site title, theme, header and footer. Logo requested: confirm it in the browser.'
}
if($SetHomepage){Set-PnPHomePage -RootFolderRelativeUrl 'SitePages/HRFlow-Home.aspx'}
Write-Host 'Provisioning finished. Review permissions, links, and branding before use.'
