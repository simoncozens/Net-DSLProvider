package Net::DSLProvider::Murphx;
use HTML::Entities qw(encode_entities_numeric);
use base 'Net::DSLProvider';
use constant ENDPOINT => "https://xml.xps.murphx.com/";
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;
__PACKAGE__->mk_accessors(qw/clientid/);

my %formats = (
    selftest => { sysinfo => { type => "text" }},
);

sub request_xml {
    my ($self, $method, $data) = @_;
    my $id = time.$$;
    my $xml = qq{<?xml version="1.0"?>
    <Request module="XPS" call="$method" id="$id" version="2.0.1"
>
        <block name="auth">
            <a name="client-id" format="counting">@{[$self->clientid]}</a>
            <a name="username" format="text">@{[$self->user]}</a>
            <a name="password" format="password">@{[$self->pass]}</a>
        </block>
};

    while (my ($block, $contents) = each %$data) {
        if ($block) { $xml .= "<block name=\"$block\">\n"; }
        for (keys %$contents) {
            die "Couldn't find format for parameter '$_' in block '$block' in method '$method'" 
            unless $formats{$method}{$block}{$_};
            $xml .= qq{<a name="$_" format="$formats{$method}{$block}{$_}">}.encode_entities_numeric($contents->{$_})."</a>\n";
        }
        if ($block) { $xml .= "</block>\n"; }
    }
    $xml .= "</Request>\n";
    return $xml;
}

sub make_request {
    my ($self, $method, $data) = @_;
    my $xml = $self->request_xml($method, $data);
    my $request = HTTP::Request->new(POST => ENDPOINT);
    $request->content_type('text/xml');
    $request->content($xml);
    if ($self->debug) { warn "Sending request: \n".$request->as_string;}
    my $resp = $ua->request($request);
    die "Request for Murphx method $method failed: " . $resp->message if $resp->is_error;
    return $resp->content;
}

1;
