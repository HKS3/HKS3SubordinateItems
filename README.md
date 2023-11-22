# koha-plugin-subordinate-items

Conditionaly creates a tab in cgi-bin/koha/catalogue/detail.pl and opac-detail.pl

showing subordinate-items via
 - MARC 773 w and/or
 - MARC 830 w

### INSTALL

 - create kpz file `zip -r hks3_subordinateitems.kpz Koha`
 - enable koha plugins (https://koha-community.org/manual/latest/en/html/plugins.html)
 - go to the Koha staff interface **More > Administration > Manage Plugins**
 - Click **Upload plugin** and select *hks3_subordinateitems.kpz* file
 - the page should reload and show the plugin. Enable it via the *Actions* dropdown menu.
 - execute the following SQL statements

### SQL

```
alter table biblio_metadata add sf773w_json varchar(100) generated always as (
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) = 0, NULL,   
   concat('[\"', replace( ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]'), ' ', '\",\"'), '\"]')   
 )) persistent;
$$

alter table biblio_metadata add sf830w_json varchar(100) generated always as (
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) = 0, NULL,
   concat('[\"', replace( ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]'), ' ', '\",\"'), '\"]')   
 )) persistent;
$$
```

```
alter table biblio_metadata add sf773w varchar(100) generated always as ( 
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) = 0, NULL, trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) ) persistent;

alter table biblio_metadata add sf830w varchar(100) generated always as ( 
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) = 0, NULL, trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) ) persistent;

alter table biblio_metadata add subord_article varchar(1) generated always as ( substr(ExtractValue(metadata,'//leader'), 8, 1) );

create index sf773w_ind on biblio_metadata (sf773w);
create index sf830w_ind on biblio_metadata (sf830w);
create index subord_article_ind on biblio_metadata (subord_article);
```

Sponsored-by: Styrian State Library
