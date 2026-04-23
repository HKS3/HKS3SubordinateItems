package Koha::Plugin::HKS3::SubordinateItems;

use Modern::Perl;

use base qw(Koha::Plugins::Base);
use Koha::Plugins::Tab;
use C4::Biblio;
use Koha::Biblios;
use Koha::Items;
use Cwd qw(abs_path);

use Mojo::JSON qw(decode_json);;

our $VERSION = "0.8";

# thanks to https://git.biblibre.com/biblibre/koha-plugin-intranet-detail-hook/src/branch/master/Koha/Plugin/Com/BibLibre/IntranetDetailHook.pm
# thanks to https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink

our $metadata = {
    name            => 'SubordinateItems Plugin',
    author          => 'Mark Hofstetter',
    date_authored   => '2020-10-25',
    date_updated    => "2026-04-08",
    minimum_version => '24.11.00.000',
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
    <script>$(document).ready(function () {
    var page = $('body').attr('ID');
    // console.log('subordinate items', page, biblionumber);
    var lang = $('html').attr('lang');
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
        addVolumeTab(biblionumber, 'opac', 'articles');
    }
    else if (page == "catalog_detail") {
        const biblionumber = new URL(window.location.href).searchParams.get('biblionumber');
        addVolumeTab(biblionumber, 'intranet');
        addVolumeTab(biblionumber, 'intranet', 'articles');
    } 
    
    // XXX ToDo translation

    function addVolumeTab(biblionumber, type, subtype = 'volumes' ) {    
        console.log('add Volume tab', type, subtype);
        // var volumes_table = '<div id="'+subtype+'">';
        var volumes_table =`
            <div id="volumes" class="tab-pane">
                <table id="volumes_table" class="display" style="width:100%">
                        <thead>
                            <tr>
                                <th>Data</th>
                                <th>Volume</th>
                                <th>Date</th>
                            </tr>
                        </thead>
                </table>
            </div>`
        ;

        var articles_table =`
            <div id="articles" class="tab-pane">
                <table id="articles_table" class="display" style="width:100%">
                </table>
            </div>`
        ;


        if (type == 'intranet') {
            var tab_classname = 'bibliodetails';
        } else  {
            var tab_classname = 'bibliodescriptions';
        }
        
        if (subtype == 'volumes') {
            var tabs = $('#'+tab_classname+' ul').append(`<li id="tab_volumes-tab" class="nav-item" role="presentation">
                <a id="tab_volumes-tab" class="nav-link" data-bs-toggle="tab" role="tab" aria-controls="tabs_volumes" aria-selected="false" data-bs-target="#volumes">Volume</a>
            </li>`);
            var volumes = $('#'+tab_classname+' .tab-content').append(volumes_table);
            $("#tab_volumes-tab").hide();

       $(function(e) {
            var ajaxData = { 'biblionumber': biblionumber,
                             'type': type, 'lang': lang};
            $.ajax({
              url: '/api/v1/contrib/subordinateitems/biblionumber/',
            type: 'GET',
            dataType: 'json',
            data: ajaxData,
        })
        .done(function(data) {
            $('a[data-bs-target="#volumes"]').text((data.label ? data.label : 'Volumes') + ' ( '+data.count+' )');
            $("#tab_volumes-tab").show();
            // $('#volumes').html(data.content);
            $('#volumes_table').DataTable( {
                "data": data.data,
                "order": [],
                "language": {
                   "url": data.datatable_lang
                },
                autoWidth: false,
                "columns": [
                    {"title": data.title ? data.title[0] : 'Data',   width: '60%' },
                    {"title": data.title ? data.title[1] : 'Volume', width: '20%' },
                    {"title": data.title ? data.title[2] : 'Year',   width: '20%' },
                ],
            } );
            })
        .error(function(data) {});
        });


        } else {
            var tabs = $('#'+tab_classname+' ul').append('<li id="tab_articles-tab" class="nav-item" role="presentation"><a id="tab_articles-tab" class="nav-link" data-bs-toggle="tab" role="tab" aria-controls="tabs_articles" aria-selected="false" data-bs-target="#articles">Article</a></li>');
            var volumes = $('#'+tab_classname+' .tab-content').append(articles_table);
            $("#tab_articles-tab").hide();

        $(function(e) {
            var ajaxData = { 'biblionumber': biblionumber,
                             'type': type, 'lang': lang, 'subtype': 'articles'};
            $.ajax({
              url: '/api/v1/contrib/subordinateitems/biblionumber/',
            type: 'GET',
            dataType: 'json',
            data: ajaxData,
        })
        .done(function(data) {
            $('a[data-bs-target="#articles"]').text((data.label ? data.label : 'Articles') + ' ( '+data.count+' )');
            $("#tab_articles-tab").show();
            $('#articles_table').DataTable( {
                "data": data.data,
                "order": [],
                "language": {
                   "url": data.datatable_lang
                },
                "columns": [ {"orderable": false} ]
            } );
            })
        .error(function(data) {});
        });
        }
    }
    });</script>
JS
    
    return $js;
}

sub intranet_js {
    my ( $self ) = @_;
    return $self->opac_js();
}
