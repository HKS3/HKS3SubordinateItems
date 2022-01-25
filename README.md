# koha-plugin-subordinate-items

Conditionaly creates a tab in cgi-bin/koha/catalogue/detail.pl and opac-detail.pl

showing subordinate-items via 
    + MARC 773 w and/or
    + MARC 830 w


SQL for speedup 


alter table biblio_metadata add sf773w_json varchar(100) generated always as (
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) = 0, NULL,
 concat( '[', replace( ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]'), ' ', ','), ']')  
 )) persistent;
$$


alter table biblio_metadata add sf830w_json varchar(100) generated always as (
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) = 0, NULL,
 concat( '[', replace( ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]'), ' ', ','), ']')  
 )) persistent;
$$



if a book MUST only be a member of one hierarchy you may use those indices

alter table biblio_metadata add sf773w varchar(100) generated always as ( 
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) = 0, NULL, trim(ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') )) ) persistent;

alter table biblio_metadata add sf830w varchar(100) generated always as ( 
if ( length( trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) = 0, NULL, trim(ExtractValue(metadata,'//datafield[@tag="830"]/subfield[@code="w"]') )) ) persistent;


create index sf773w_ind on biblio_metadata (sf773w);
create index sf830w_ind on biblio_metadata (sf830w);

Sponsored-by: Styrian State Library
