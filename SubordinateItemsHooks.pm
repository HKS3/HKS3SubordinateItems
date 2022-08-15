package Koha::Plugin::HKS3SubordinateItems::SubordinateItemsHooks;

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
        // console.log('alread set ',biblionumber); 
        addVolumeTab(biblionumber, 'intranet');
    } 
    
    // XXX ToDo translation

    function addVolumeTab(biblionumber, type, subtype = 'volumes' ) {    
        console.log('add Volume tab', type, subtype);
        // var volumes_table = '<div id="'+subtype+'">';
        var volumes_table =`
            <div id="volumes" class="table-striped">
                <table id="volumes_table" class="display" style="width:100%">
                        <thead>
                            <tr>
                                <th>Data</th>
                                <th>Volume</th>
                                <th>Date</th>
                                <th>Covers</th>
                            </tr>
                        </thead>
                </table>
            </div>`
        ;

        var articles_table =`
            <div id="articles" class="table-striped">
                <table id="articles_table" class="display" style="width:100%">
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


        if (type == 'intranet') {
            var tab_classname = 'bibliodetails';
        } else  {
            var tab_classname = 'bibliodescriptions';
        }
        
        if (subtype == 'volumes') {
            var tabs = $('#'+tab_classname+' ul')
                .append('<li id="tab_volumes"><a id="vol_label" href="#volumes">Volume</a></li>');
            var volumes = $('#'+tab_classname)
              .append(volumes_table);
            $("#tab_volumes").hide();

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
            $('#vol_label').text((data.label ? data.label : 'Volumes')
                                   + ' ( '+data.count+' )');
            $("#tab_volumes").show();
            // $('#volumes').html(data.content);
            $('#volumes_table').DataTable( {
                "data": data.data,
                "order": [],
                "language": {
                   "url": data.datatable_lang
                },
                "columns": [
                    {"title": data.title ? data.title[0] : 'Data'},
                    {"title": data.title ? data.title[1] : 'Volume'},
                    {"title": data.title ? data.title[2] : 'Year'},
                    {"title": data.title ? data.title[3] : 'Cover'}
                    ]
            } );
            })
        .error(function(data) {});
        });


        } else {
            var tabs = $('#'+tab_classname+' ul')
                .append('<li id="tab_articles"><a id="articles_label" href="#articles">Articles</a></li>');
            var articles = $('#'+tab_classname)
                .append(articles_table);
            $("#tab_articles").hide();

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
            $('#articles_label').text((data.label ? data.label : 'Articles')
                                   + ' ( '+data.count+' )');
            $("#tab_articles").show();
            $('#articles_table').DataTable( {
                "data": data.data,
                "order": [],
                "language": {
                   "url": data.datatable_lang
                },
                "columns": [
                    {"title": data.title ? data.title[0] : 'Data'},
                    {"title": data.title ? data.title[1] : 'Volume'},
                    {"title": data.title ? data.title[2] : 'Year'}
                    ]
            } );
            })
        .error(function(data) {});
        });
        }
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
<on(e) {
            var ajaxData = { 'biblionumber': biblionumber,
                             'type': type, 'lang': lang};
            $.ajax({
              url: '/api/v1/contrib/subordinateitems/biblionumber/',
            type: 'GET',
            dataType: 'json',
            data: ajaxData,
        })
        .done(function(data) {
            $('#vol_label').text((data.label ? data.label : 'Volumes')
                                   + ' ( '+data.count+' )');
            $("#tab_volumes").show();
            // $('#volumes').html(data.content);
            $('#volumes_table').DataTable( {
                "data": data.data,
                "order": [],
                "language": {
                   "url": data.datatable_lang
                },
                "columns": [
                    {"title": data.title ? data.title[0] : 'Data'},
                    {"title": data.title ? data.title[1] : 'Volume'},
                    {"title": data.title ? data.title[2] : 'Year'},
                    {"title": data.title ? data.title[3] : 'Cover'}
                    ]
            } );
            })
        .error(function(data) {});
        });
id="example" class="display" style="width:100%">
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
