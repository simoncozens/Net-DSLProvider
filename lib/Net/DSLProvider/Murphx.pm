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
    service_details => {"" => { "service-id" => "counting" }},
    requestmac => {"" => { "service-id" => "counting", "reason" => "text" }},
    cease => {"" => { "service-id" => "counting", "reason" => "text",
        "client-ref" => "text", "crd" => "datetime", "accepts-charges" => "yesno" }},
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
                street city county sub-premise/),
            postcode => "postcode", telephone => "phone", 
            mobile => "phone", fax => "phone", email => "email"
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
    return %services;
}

=head2 cease

    $murphx->cease( "service-id" => 12345, "reason" => "This service is no longer required"
        "client-ref" => "ABX129", "crd" => "1970-01-01", "accepts-charges" => 'Y' );

Places a cease order to terminate the ADSL service completely. 

Required parameters are : service-id, crd, client-ref

Returns order-id which is the ID of the cease order for tracking purposes.

=cut

sub cease {
    my ($self, $args) = @_;

    return undef unless $args;
    for (qw/service-id crd client-ref/) {
        if (!$args->{$_}) { die "You must provide the $_ parameter"; }
        }

    my $response = $self->make_request("cease", $args);

    return $response->{a}->{"order-id"}->{content};
}

=head2 requestmac

    $murphx->requestmac( "service-id" => 12345, "reason" => "EU wishes to change ISP" );

Obtains a MAC for the given service You must pass the service-id. The "reason" parameter
is optional.

Returns a hash comprising: mac expiry-date

=cut

sub requestmac {
    my ($self, $service, $reason) = @_;
    return undef unless $service;

    $reason = "EU wishes to change ISP" unless $reason;

    my $response = $self->make_request("requestmac", {
        "service-id" => $service, "reason" => $reason
    });

    my %mac = ();

    $mac{mac} = $response->{a}->{mac}->{content};
    $mac{"expiry-date"} = $response->{a}->{"expiry-date"}->{content};

    return %mac;
}

sub order_history { goto &order_eventlog_history }

=head2 order_eventlog_history
    
    $murphx->order_eventlog_history( "order-id" => 12345 );

Gets order history

Returns an array, each element of which is a hash showing the next update in date
sorted order. The hash keys are date, name and value.

=cut

sub order_eventlog_history {
    my ($self, $order) = @_;
    return undef unless $order;
    my $response = $self->make_request("order_eventlog_history", { "order-id" => $order });

    my @history = ();

    while ( my $a = shift @{$response->{block}{block}} ) {
        foreach (keys %{$a}) {
            my %u = ();
            $u{date} = $a->{'a'}->{'date'}->{'content'};
            $u{name} = $a->{'a'}->{'name'}->{'content'};
            $u{value} = $a->{'a'}->{'value'}->{'content'};

            push(@history, \%u);
        }
    }
    return @history;
}

=head2 order_status

    $murphx->order_status( "order-id" => 12345 );

Get's status of an order specified by "order-id" from Murphx

Returns a hash containing a hash order and a hash customer
The order hash contains:
    order-id, service-id, client-ref, order-type, cli, service-type, service,
    username, status, start, finish, last-update

The customer hash contains:
    forename, surname, address, city, county, postcode, telephone, building

=cut

sub order_status {
    my ($self, $order) = @_;
    return undef unless $order;
    my $response = $self->make_request("order_status", {
        "order-id" => $order
        });

    my %order = ();
    foreach (keys %{$response->{block}->{order}->{a}} ) {
        $order{order}{$_} = $response->{block}->{order}->{a}->{$_}->{content};
        }
    foreach (keys %{$response->{block}->{customer}->{a}} ) {
        $order{customer}{$_} = $response->{block}->{customer}->{a}->{$_}->{content};
        }
    return %order;
}

=head2 service_details 

    $murphx->service_details( "service-id" => 12345 );

Obtains details of the service identified by "service-id" from Murphx

Returns a hash with details including (but not limited to):
    activation-date, cli, care-level, technology-type, service-id
    username, password, live, product-name, ip-address, product-id
    cidr

=cut

sub service_details {
    my ($self, $service) = @_;
    return undef unless $service;
    my $response = $self->make_request("service_details", {
        "service-id" => $service, "detailed" => 'Y'
        });

    my %details = ();
    foreach (keys %{$response->{block}->{a}} ) {
        $details{$_} = $response->{block}->{a}->{$_}->{content};
        }
    return %details;
}


=head2 order

    $murphx->order(
        # Customer details
        forename => "Clara", surname => "Trucker", 
        building => "123", street => "Pigeon Street", city => "Manchester", 
        county => "Greater Manchester", postcode => "M1 2JX",
        telephone => "01614960213", 
        # Order details
        clid => "01614960213", "client-ref" => "claradsl", 
        "prod-id" => $product, crd => $leadtime, username => "claraandhugo",
        password => "skyr153", "care-level" => "standard", 
        realm => "surfdsl.net"
    );

Submits an order for DSL to be provided to the specified phone line.
Note that all the parameters above must be supplied. CRD is the
requested delivery date in YYYY-mm-dd format; you are responsible for
computing dates after the minimum lead time. The product ID should have
been supplied to you by Murphx.

Additional parameters are listed below and described in the integration
guide:

    title street company mobile email fax sub-premise fixed-ip routed-ip
    allocation-size hardware-product max-interleaving test-mode
    inclusive-transfer

=cut

sub order {
    my ($self, $data_in) = @_;
    # We expect it "flat" and arrange it into the right blocks as we check it
    my $data = {};
    for (qw/forename surname building city county postcode telephone/) {
        if (!$data_in->{$_}) { die "You must provide the $_ parameter"; }
        $data->{customer}{$_} = $data_in->{$_};
    }
    defined $data_in->{$_} and $data->{customer}{$_} = $data_in->{$_} 
        for qw/title street company mobile email fax sub-premise/;

    for (qw/clid client-ref prod-id crd username/) {
        if (!$data_in->{$_}) { die "You must provide the $_ parameter"; }
        $data->{order}{$_} = $data_in->{$_};
    }

    for (qw/password realm care-level/) {
        if (!$data_in->{$_}) { die "You must provide the $_ parameter"; }
        $data->{order}{attributes}{$_} = $data_in->{$_};
    }
    defined $data_in->{$_} and $data->{order}{attributes}{$_} = $data_in->{$_} 
        for qw/fixed-ip routed-ip allocation-size hardware-product
            max-interleaving test-mode inclusive-transfer/;
    $self->make_request("provide", $data);
}

1;
