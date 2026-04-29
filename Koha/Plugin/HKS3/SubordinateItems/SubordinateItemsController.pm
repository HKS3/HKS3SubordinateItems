package Koha::Plugin::HKS3::SubordinateItems::SubordinateItemsController;

use Mojo::Base 'Mojolicious::Controller';

use C4::Context;
use C4::Biblio qw(GetXmlBiblio);
use C4::XSLT;

use C4::External::Amazon;

use Koha::Biblios;
use Koha::Items;
use Mojo::JSON qw(decode_json encode_json);

my $translate = {
    'de-DE' => 
        {dt      => 'https://cdn.datatables.net/plug-ins/1.10.21/i18n/German.json',
         columns => ['Daten', 'Band', 'Jahr', 'Cover', 'Signatur'],
         label   => 'Bände',
        },
    'si-SI' => 
        {dt      => 'https://cdn.datatables.net/plug-ins/1.10.21/i18n/Slovenian.json',
        }
};

sub get {
    my $c = shift->openapi->valid_input or return;
    my $biblionumber = $c->validation->param('biblionumber');
    my $type  = $c->validation->param('type');
    my $lang_query  = $c->validation->param('lang');
    my $subtype  = $c->validation->param('subtype') // 'volumes';
    my $record = Koha::Biblios->find($biblionumber)->record;

    my $dbh = C4::Context->dbh;
    
    my $controlfield = $record->field('001');
    unless ($controlfield) {
        return $c->render( status => 404, openapi => {} );
    }
    
    my $internalid = $controlfield->data;
    my $search = sprintf('"%s"', $controlfield->data); 
    if ($subtype eq 'articles') {
        $translate->{'de-DE'}->{'label'} = 'Artikel';
    } else {
        $translate->{'de-DE'}->{'label'} = 'Bände';
    }

    my $newquery = <<"SQL";
    SELECT r.biblionumber
         , r.id as record_id
         , f.id as field_id
         , f.tag
         , s.code
    FROM nm2db_records r
    JOIN nm2db_fields f ON f.record_id = r.id
    JOIN nm2db_subfields s ON s.field_id = f.id
    JOIN biblio_metadata bm ON bm.biblionumber = r.biblionumber
    WHERE s.value = ?
    AND ((f.tag = '773' and s.code = 'w') or (f.tag = '830' and s.code = 'w'))
    ORDER BY tag
SQL
    my $subords_query = $dbh->prepare($newquery);
    $subords_query->execute($controlfield->data);
    my $dbitems = $subords_query->fetchall_arrayref({});

    my @items;
    for my $item (@$dbitems) {
        my ($is_article) = $dbh->selectrow_array(q[
            SELECT substr(value, 8, 1) = 'a'
            FROM nm2db_fields f
            JOIN nm2db_subfields s ON f.id = s.field_id
            WHERE f.record_id = ?
            AND f.tag = 'leader'
        ], {}, $item->{record_id});
        next if ($subtype eq 'articles') != $is_article;

        # our preference is 830v, 773g, 773q. There'll never be both 830 and 773 at the same time at this point, so alphabetical order of codes works for us
        my ($volume) = $dbh->selectrow_array(q[
            SELECT value FROM nm2db_subfields
            WHERE field_id = ?
            AND code in ('v', 'g', 'q')
            ORDER BY code LIMIT 1
        ], {}, $item->{field_id});

        my ($pub_date) = $dbh->selectrow_array(q[
            SELECT value FROM nm2db_fields f
            JOIN nm2db_subfields s ON f.id = s.field_id
            WHERE f.record_id = ?
            AND f.tag = 264
            AND f.indicator2 = '1'
            AND s.code = 'c'
        ], {}, $item->{record_id});

        my ($pages) = $dbh->selectrow_array(q[
            SELECT value FROM nm2db_fields f
            JOIN nm2db_subfields s ON f.id = s.field_id
            WHERE f.record_id = ?
            AND f.tag = 300
            AND s.code = 'a'
        ], {}, $item->{record_id});

        my ($isbn, $item_desc) = $dbh->selectrow_array(q[
            SELECT isbn, GROUP_CONCAT(CONCAT_WS(' ', coded_location_qualifier, itemcallnumber, if(notforloan=0, '', '[Nicht entlehnbar]')) SEPARATOR ' <br> ') item
            FROM biblioitems bi
            LEFT JOIN items i ON bi.biblionumber = i.biblionumber
            WHERE bi.biblionumber = ?
            GROUP BY isbn
        ], {}, $item->{biblionumber});

        push @items, {
            biblionumber => $item->{biblionumber},
            isbn         => $isbn,
            item         => $item_desc,
            pub_date     => $pub_date,
            volume       => $volume,
            pages        => $pages,
        };
    }

    unless (@items) {
        return $c->render( status => 404, openapi => {} );
    }

    my $htdocs;
    if ($type eq 'intranet') {
        $htdocs = C4::Context->config('intrahtdocs');
    } else {
        $htdocs = C4::Context->config('opachtdocs');
    }

    my $xsl;

    if ($subtype eq 'articles') {
        $xsl = 'MARC21slim2subordinateArticle.xsl';
        @items = sort {
            # first page number matters
            my ($apages) = $a->{pages} =~ /(\d+)/;
            my ($bpages) = $b->{pages} =~ /(\d+)/;
            $apages <=> $bpages
        } @items;
    } else {
        $xsl = 'MARC21slim2subordinateVolume.xsl';
        @items = sort { # pub_date asc, volume asc. cmp because they aren't necessarily numbers
            my $apubdate = $a->{pub_date} =~ /(\d+)/;
            my $bpubdate = $b->{pub_date} =~ /(\d+)/;
            ($apubdate <=> $bpubdate) or ($a->{volume} cmp $b->{volume})
        } @items;
    }

    my ($theme, $lang) = C4::Templates::themelanguage($htdocs, $xsl, $type);
    $lang = $lang_query if $lang_query;
    
    $xsl = "$htdocs/$theme/$lang/xslt/$xsl";
    
    my $i = 0;
    my $data = [];
    foreach my $item (@items) {
        $i++;
        my $xml = GetXmlBiblio($item->{biblionumber});

        # Stolen from C4::XSLT::XSLTParse4Display, so that syspresfs like UseControlNumber apply
        my $sysxml = C4::XSLT::get_xslt_sysprefs();
        $xml =~ s{</record>}{$sysxml</record>};

        my $biblioitem = Koha::Biblioitems->find({ 'biblionumber' => $item->{biblionumber} });
        my $isbn = C4::Koha::GetNormalizedISBN($biblioitem->isbn); # $isbn =~ s/\D//g;
        my $cr = C4::XSLT::engine->transform($xml, $xsl);
        push(@$data, [
            $cr,
            $item->{volume},
            $item->{pub_date}, 
            ($isbn ? image_link($isbn, '', $i) : ''),
            $item->{item},  
        ]);
    }

    return $c->render( status => 200, openapi => {
        count => $i,
        data => $data,
        datatable_lang => $translate->{$lang}->{dt},
        lang => $lang, 
        title => $translate->{$lang}->{columns}, 
        label => $translate->{$lang}->{label}, 
    } );
}

sub image_link {
    my $isbn = shift;
    my $title = shift;
    my $link = '<div></div>';
    my $index = shift;

    if ( C4::Context->preference('OPACAmazonCoverImages') ) {
        my $amazon_link = '<a href="http://www.amazon%s/gp/reader/%s%s';
        if (C4::Context->preference('OPACURLOpenInNewWindow')) {
            $amazon_link .= '#reader-link" target="_blank" rel="noreferrer">'
        } else {
            $amazon_link .= '">'
        }

        my $cover_html = <<"HTML";
<div class='bookcoverimg' id='amazon-bookcoverimg-$index'>
      <a href='https://images-na.ssl-images-amazon.com/images/P/$isbn.01.LZZZZZZZ.jpg' title='Amazon cover image'>
      <img src='https://images-na.ssl-images-amazon.com/images/P/$isbn.01.MZZZZZZZ.jpg' alt='Amazon cover image' 
          data-link='http://www.amazon.com/gp/reader/$isbn#reader-link'/>
      </a>


      <div class='hint'>Image from Amazon.com</div>
</div>
HTML

        $link = $cover_html;
    }

    if ( C4::Context->preference('GoogleJackets') ) {
        $link .= sprintf('<div title="%s" class="%s" id="gbs-thumbnail-preview"></div>', $isbn,$isbn);
        $link .= sprintf('<div class="google-books-preview">
<img border="0" src="https://books.google.com/books/content?vid=ISBN%s&printsec=frontcover&img=1&zoom=1"/></div>', $isbn);
    }

    return $link;
}      

1;

__END__
    select * from ( SELECT biblionumber,
    ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') AS ITEM FROM biblio_metadata ) rel
    where item like ?

