package Net::DSLProvider::Murphx;
use HTML::Entities qw(encode_entities_numeric);
use base 'Net::DSLProvider';
use constant ENDPOINT => "https://xml.xps.murphx.com/";
use LWP::UserAgent;
use XML::Simple;
my $ua = LWP::UserAgent->new;
__PACKAGE__->mk_accessors(qw/clientid/);

my %formats = (
    selftest => { sysinfo => { type => "text" }},
    availability => { "" => { cli => "phone", detailed => "yesno",
        ordertype => "text" } },
    order_status => { "" => { "order-id" => "counting" }},
    order_eventlog_history => { "" => { "order-id" => "counting" }},
    provide => { 
        order => {   
            "client-ref" => "text", cli => "phone", "prod-id" => "counting",
            crd => "date", username => "text", 
            attributes => {
                password => "password", realm => "text", 
                "fixed-ip" => "yesno", "routed-ip" => "yesno", 
                "allocation-size" => "counting", "care-level" => "text",
                "hardware-product" => "counting", 
                "max-interleaving" => "text", "test-mode" => "yesno",
                "inclusive-transfer" => "counting"
            }
        }, customer => { 
            (map { $_ => "text" } qw/title forename surname company building
                street city county/),
            "sub-premise" => "text", postcode => "postcode", 
            telephone => "phone", mobile => "phone", fax => "phone",
            email => "email"
        }
    }
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

    my $recurse;
    $recurse = sub {
        my ($format, $data) = @_;
        while (my ($key, $contents) = each %$format) {
            if (ref $contents eq "HASH") {
                if ($key) { $xml .= "<block name=\"$key\">\n"; }
                $recurse->($contents, $data->{$key});
                if ($key) { $xml .= "</block>\n"; }
            } else {
                $xml .= qq{<a name="$key" format="$contents">}.encode_entities_numeric($data->{$key})."</a>\n" 
                if $data->{$key};
            }
        }
    };
    $recurse->($formats{$method}, $data); 
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
    my $resp_o = XMLin($resp->content);
    if ($resp_o->{status}{no} > 0) { die  $resp_o->{status}{text} };
    return $resp_o;
}

sub services_available {
    my ($self, $number) = @_;
    my $response = $self->make_request("availability", { 
        cli => $number, detailed => "N", ordertype => "migrate" 
    });
    if ( $response->{block}->{availability}->{block}->{exchange}->{a}->{name}->{content} eq 'POPLAR' ) {
        die "Services not available at POPLAR exchange due to BTO capacity issues"
    }

    my %services;
    while ( my $a = pop @{$response->{block}->{leadtimes}->{block}} ) {
        $services{$a->{a}->{'product-id'}->{content}} = 
            $a->{a}->{'first-date-text'}->{content};
    }

}

1;
