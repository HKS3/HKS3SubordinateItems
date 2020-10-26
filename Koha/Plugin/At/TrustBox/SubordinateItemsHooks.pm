package Koha::Plugin::At::TrustBox::SubordinateItemsHooks;

use base qw(Koha::Plugins::Base);
use Koha::Plugins::Tab;
use C4::Biblio;
use Koha::Biblios;
use Koha::Items;


our $VERSION = "0.1";

# thanks to https://git.biblibre.com/biblibre/koha-plugin-intranet-detail-hook/src/branch/master/Koha/Plugin/Com/BibLibre/IntranetDetailHook.pm

our $metadata = {
    name            => 'SubordinateItems Plugin',
    author          => 'Mark Hofstetter',
    date_authored   => '2020-10-25',
    date_updated    => "2020-10-26",
    minimum_version => '19.05.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'this plugin selects subordinate items based on MARC773w and displays them in a separate tab in intranet'
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    $self->{cgi} = CGI->new();

    return $self;
}

sub intranet_catalog_biblio_tab {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my @tabs;
    
    my $biblionumber = $cgi->param('biblionumber');
    $biblionumber = HTML::Entities::encode($biblionumber);
    # cgi-bin/catalogue/showmarc.pl

    my $record       = GetMarcBiblio({ biblionumber => $biblionumber });
    my $dbh = C4::Context->dbh;

    my $controlfield = $record->field('001');

    my $internalid = $controlfield->data;

    my $query= <<'SQL';
    select * from ( SELECT biblionumber,
    ExtractValue(metadata,'//datafield[@tag="773"]/subfield[@code="w"]') AS ITEM FROM biblio_metadata ) rel
    where item like ?
SQL

    my $queryitem = $dbh->prepare($query);
    $queryitem->execute($controlfield->data .'%');
    my $items = $queryitem->fetchall_arrayref({});

    return 0 unless scalar(@$items) > 0;    

    my $xsl = 'MARC21slim2intranetResults.xsl';
    my $htdocs = C4::Context->config('intrahtdocs');
    my ($theme, $lang) = C4::Templates::themelanguage($htdocs, $xsl, 'intranet');
    $xsl = "$htdocs/$theme/$lang/xslt/$xsl";

    my $content = '';

    foreach my $item (@$items) {
      my $xml = GetXmlBiblio($item->{biblionumber});
        $content .=  Encode::encode_utf8(C4::XSLT::engine->transform($xml, $xsl));
    }

    push @tabs,
      Koha::Plugins::Tab->new(
        {
            title   => 'Teile',
            content => $content,
        }
      );

    return @tabs;
}
