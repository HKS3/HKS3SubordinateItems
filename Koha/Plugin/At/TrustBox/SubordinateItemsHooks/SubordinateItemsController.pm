package Koha::Plugin::At::TrustBox::SubordinateItemsHooks::SubordinateItemsController;

use Mojo::Base 'Mojolicious::Controller';

use C4::Context;
use C4::Debug;
use C4::Output qw(:html :ajax pagination_bar);
use C4::Biblio;
use C4::XSLT;

use C4::Biblio;
use C4::XSLT;

use Koha::Biblios;
use Koha::Items;
use Mojo::JSON qw(decode_json encode_json);

sub get {
    my $c = shift->openapi->valid_input or return;
    my $biblionumber = $c->validation->param('biblionumber');
    my $record       = GetMarcBiblio({ biblionumber => $biblionumber });
    my $dbh = C4::Context->dbh;
    
    my $controlfield = $record->field('001');
    
    my $internalid = $controlfield->data;

    # 773

    
    my $sql= <<'SQL';
select * from ( SELECT bm.biblionumber,
    ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') AS ITEM,
    ExtractValue(metadata,'//datafield[@tag="490"]/subfield[@code="v"]') AS volume,
    ExtractValue(metadata,'//datafield[@tag="264"]/subfield[@code="c"]') AS pub_date,
    isbn
  FROM biblio_metadata bm 
        join biblioitems bi on bi.biblionumber = bm.biblionumber) rel
    where item like ?
    order by volume desc, pub_date desc
SQL
    # implement ordering
    my $queryitem = $dbh->prepare($sql);
    $queryitem->execute($controlfield->data .'%');
    my $items = $queryitem->fetchall_arrayref({});
    
    return 0 unless scalar(@$items) > 0;
    
    my $xsl = 'MARC21slim2OPACResults.xsl';
    my $htdocs = C4::Context->config('opachtdocs');
    my ($theme, $lang) = C4::Templates::themelanguage($htdocs, $xsl, 'opac');
    $xsl = "$htdocs/$theme/$lang/xslt/$xsl";
    
    my $content = '';
    my $isbns = [];
    my $i = 0;
    my $data = [];
    foreach my $item (@$items) {
        $i++;
        my $xml = GetXmlBiblio($item->{biblionumber});
        $content = C4::XSLT::engine->transform($xml, $xsl);
        push(@$isbns, $item->{isbn});
    }


    return $c->render( status => 200, openapi => 
        { content => $content, count => $i, ibsns => $isbns } );
}

1;

__END__
    select * from ( SELECT biblionumber,
    ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') AS ITEM FROM biblio_metadata ) rel
    where item like ?

