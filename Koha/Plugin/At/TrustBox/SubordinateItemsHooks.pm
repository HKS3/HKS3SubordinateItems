package Koha::Plugin::At::TrustBox::SubordinateItemsHooks;

use Modern::Perl;

use base qw(Koha::Plugins::Base);
use Koha::Plugins::Tab;
use C4::Biblio;
use Koha::Biblios;
use Koha::Items;
use Cwd qw(abs_path);

use Mojo::JSON qw(decode_json);;

our $VERSION = "0.2";

# thanks to https://git.biblibre.com/biblibre/koha-plugin-intranet-detail-hook/src/branch/master/Koha/Plugin/Com/BibLibre/IntranetDetailHook.pm
# thanks to https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink

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

sub intranet_catalog_biblio_tab_obsolete {
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


sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;

    return 'subordinateitems';
}

sub static_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}


sub opac_head {
    my ( $self ) = @_;

    return q|
<link href="/opac-tmpl/bootstrap/css/datatables-intra.css" rel="stylesheet" type="text/css">
    |;
}


sub opac_js {
    my ( $self ) = @_;

    my $js = <<'JS';
    <script>
    var page = $('body').attr('ID');
    console.log('subordinate items', page, biblionumber);
    if (page == "opac-detail") {
        // "if" statment may/has to be removed when 
        // https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=27029
        // is in koha

        var biblionumber = $("div#catalogue_detail_biblio").data("biblionumber");
        if (!biblionumber) {
            var x = document.getElementsByClassName("unapi-id")[0]
                        .getAttribute("title");
            biblionumber = x.split(':')[2];
        }
        addVolumeTab(biblionumber, 'opac');
    }
    else if (page == "catalog_detail") {
        console.log('alread set ',biblionumber); 
        addVolumeTab(biblionumber, 'intranet');
    } 
    


    function addVolumeTab(biblionumber, type) {    
        // console.log('add Volume tab');
        // var volumes_table = '<div id="volumes">';
        var volumes_table =`
            <div id="volumes" class="table-striped">
                <table id="volumes_table" class="display" style="width:100%">
                        <thead>
                            <tr>
                                <th>Volumes</th>
                                <th>Covers</th>
                            </tr>
                        </thead>
                </table>
            </div>`
        ;

        if (type == 'intranet') {
            var tab_classname = 'bibliodetails';
        } else  {
            var tab_classname = 'bibliodescriptions';
        }
        
        var tabs = $('#'+tab_classname+' ul')
            .append('<li id="tab_volumes"><a id="vol_label" href="#volumes">Volumes</a></li>');

        var volumes = $('#'+tab_classname)
            .append(volumes_table);
        $("#tab_volumes").hide();


        // console.log('subordinate items', biblionumber);
        //$("#tab_volumes").on("click", function(e) {
        $(function(e) {
            // var ajaxData = '';
            var ajaxData = { 'biblionumber': biblionumber, 'type': type};
            $.ajax({
              // url: '/api/v1/contrib/subordinateitems/biblionumber/'+biblionumber,
              url: '/api/v1/contrib/subordinateitems/biblionumber/',
            type: 'GET',
            dataType: 'json',
            data: ajaxData,
        })
        .done(function(data) {
            $('#vol_label').text('Volumes ( '+data.count+' )');
            $("#tab_volumes").show();
            // $('#volumes').html(data.content);
            $('#volumes_table').DataTable( {
                "data": data.data
            } );
            
            })
        .error(function(data) {});
        });
    }
    </script>
JS
    
    return $js;
}

sub intranet_js {
    my ( $self ) = @_;
    return $self->opac_js();
}

__END__
<table id="example" class="display" style="width:100%">
        <thead>
            <tr>
                <th>Name</th>
                <th>Position</th>
                <th>Office</th>
                <th>Extn.</th>
                <th>Start date</th>
                <th>Salary</th>
            </tr>
        </thead>
        <tfoot>
            <tr>
                <th>Name</th>
                <th>Position</th>
                <th>Office</th>
                <th>Extn.</th>
                <th>Start date</th>
                <th>Salary</th>
            </tr>
        </tfoot>
    </table>
