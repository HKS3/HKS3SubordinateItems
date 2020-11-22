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
    my $type  = $c->validation->param('type');
    my $record       = GetMarcBiblio({ biblionumber => $biblionumber });
    my $dbh = C4::Context->dbh;
    
    my $controlfield = $record->field('001');
    
    my $internalid = $controlfield->data;

    # 773

    my $amazon_link = '<img border="0" src="https://images-na.ssl-images-amazon.com/images/P/%d.01.MZZZZZZZ.jpg" alt="Cover image" /></a>';

    
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
    
    my $xsl;
    my $htdocs;
    if ($type eq 'intranet') {
        $xsl = 'MARC21slim2intranetResults.xsl';
        $htdocs = C4::Context->config('intrahtdocs');
    } else {
        $xsl = 'MARC21slim2OPACResults.xsl';
        $htdocs = C4::Context->config('opachtdocs');
    }

    my ($theme, $lang) = C4::Templates::themelanguage($htdocs, $xsl, $type);
    $xsl = "$htdocs/$theme/$lang/xslt/$xsl";
    
    my $content = '';
    my $isbns = [];
    my $i = 0;
    my $data = [];
    foreach my $item (@$items) {
        $i++;
        my $xml = GetXmlBiblio($item->{biblionumber});
        my $biblioitem =  Koha::Biblioitems
                ->find( { 'biblionumber' => $item->{biblionumber} } );
        my $isbn = C4::Koha::GetNormalizedISBN($biblioitem->isbn);
        $isbn =~ s/\D//g;
        my $cr = C4::XSLT::engine->transform($xml, $xsl);
        push(@$data, [$cr, sprintf($amazon_link, $isbn)]);
        $content .= $cr;
    }


    return $c->render( status => 200, openapi => 
        { content => $content, count => $i, ibsns => $isbns, data => $data,
         } );
}

1;

__END__
    select * from ( SELECT biblionumber,
    ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') AS ITEM FROM biblio_metadata ) rel
    where item like ?

