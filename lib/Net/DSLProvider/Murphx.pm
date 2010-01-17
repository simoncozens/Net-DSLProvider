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
    order_eventlog_changes => { "" => { "date" => "datetime" }},
    woosh_request_oneshot => {"" => { "service-id" => "counting",
        "fault-type" => "text", "has-worked" => "yesno", "disruptive" => "yesno",
        fault-time" => "datetime" }},
    woosh_list => {"" => { "service-id" => "counting" }},
    woosh_response => {"" => { "woosh-id" => "counting" }},
    change_password => {"" => { "service-id" => "counting", "password" => "password" }},
    service_details => {"" => { "service-id" => "counting" }},
    service_view => {"" => { "service-id" => "counting" }},
    service_usage_summary => {"" => { "service-id" => "counting", 
        "year" => "counting", "month" => "text" }},
    service_auth_log => {"" => { "service-id" => "counting", "rows" => "counting" }},
    service_eventlog_changes => {"" => { "start-date" => "datetime", "stop-date" => "datetime" }},
    service_eventlog_history => { "" => { "service-id" => "counting" }},
    requestmac => {"" => { "service-id" => "counting", "reason" => "text" }},
    cease => {"" => { "service-id" => "counting", "reason" => "text",
        "client-ref" => "text", "crd" => "datetime", "accepts-charges" => "yesno" }},
    modify => {
        order => {
            "service-id" => "counting", "client-ref" => "text", "crd" => "date",
            "prod-id" => "counting", "cli" => "phone",
            attributes => { "care-level" => "text", "inclusive-transfer" => "counting",
                "test-mode" => "yesno" },
        }
    },
    order => { 
        order => {   
            "client-ref" => "text", cli => "phone", "prod-id" => "counting",
            crd => "date", username => "text", 
            attributes => {
                password => "password", realm => "text", 
                "fixed-ip" => "yesno", "routed-ip" => "yesno", 
                "allocation-size" => "counting", "care-level" => "text",
                "hardware-product" => "counting", 
                "max-interleaving" => "text", "test-mode" => "yesno",
                "mac" => "text", "losing-isp" => "text",
                "inclusive-transfer" => "counting", "pstn-order-id" => "text"
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
    <Request module="XPS" call="$method" id="$id" version="2.0.1">
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

    my %services;
    while ( my $a = pop @{$response->{block}->{leadtimes}->{block}} ) {
        $services{$a->{a}->{'product-id'}->{content}} = 
            $a->{a}->{'first-date-text'}->{content};
    }
    return %services;
}

=head2 modify

    $murphx->modify(
        "service-id" => "12345", "client-ref" => "myref", "prod-id" => "1000",
        "crd" => "2009-12-31", "care-level" => "standard" "inclusive-transfer" => "3",
        "test-mode" = "N" );

Modify the service specificed in service-id. Parameters are as per the Murphx documentation

Returns order-id for the modify order.

=cut

sub modify {
    my ($self, $args) = @_;
    for (qw/ service-id client-ref myref prod-id crd care-level inclusive-transfer test-mode /) {
        if ( ! $args->{$_} ) { die "You must provide the $_ parameter"; }
    }

    my $response = $self->make_request("modify", $data);

    return $response->{a}->{"order-id"}->{content};
}

=head2 change_password 

    $murphx->change_password( "service-id" => "12345", "password" => "secret" );

Changes the password for the ADSL login on the given service.

Requires service-id and password

Returns 1 for successful password change.

=cut

sub change_password {
    my ($self, $args) = @_;
    for (qw / service-id password /) {
        if ( !$args->{$_} ) { die "You must provide the $_ parameter"; }
    }

    my $response = $self->make_request("change_password", $args);

    return undef unless $response={status}{no} == 0;
    return 1;
}

=head2 woosh_response

    $murphx->woosh_response( "12345" );

Obtains the results of a Woosh test, previously requested using request_woosh(). Takes
the ID of the woosh test as it's only parameter. Note that this will only return results
for completed Woosh tests. Use woosh_list() to determine if the woosh test is completed.

Returns an hash containing a hash for each set of test results. See Murphx documentation for 
details of the test result fields.

=cut

sub woosh_response {
    my ($self, $wooshid) = @_;
    return undef unless $wooshid;

    my $response = $self->make_request("woosh_response", { "woosh-id" => $wooshid });

    my %results = ();
    foreach ( keys %{$response->{block}->{block}} ) {
        my $b = $_;
        foreach ( keys %{$response->{block}->{block}->{$b}->{a}} ) {
            $results{$b}{$_} = $response->{block}->{block}->{$b}->{a}->{$_}->{content};
        }
    }
    return %results;
}

=head2 woosh_list

    $murphx->woosh_list( "12345" );

Obtain a list of all woosh tests requested for the given service-id and their status.

Requires service-id as the single parameter.

Returns an array each element of which is a hash containing the following fields for each requested
Woosh test:
    service-id woosh-id start-time stop-time status

The array elements are sorted by date with the most recent being first.

=cut

sub woosh_list {
    my ($self, $service) = @_;
    return undef unless $service;

    my $response = $self->make_request("woosh_list", { "service-id" => $service });

    my @list = ();
    if ( ref $response->{block}->{block} eq "ARRAY" ) {
        while ( my $b = shift @{$response->{block}->{block}} ) {
            my %a = ();
            foreach ( keys %{$b->{a}} ) {
                $a{$_} = $b->{a}->{$_}->{content};
            }
            push @list, \%a;
        }
    } else {
        my %a = ();
        foreach ( keys %{$response->{block}->{block}->{a}} ) {
            $a{$_} = $response->{block}->{block}->{a}->{$_}->{content};
        }
        push @list, \%a;
    }

    return @list;
}

=head2 request_woosh

    $murphx->request_woosh( "service-id" => "12345", "fault-type" => "EPP",
        "has-worked" => "Y", "disruptive" => "Y", "fault-time" => "2007-01-04 15:33:00");

Alias to woosh_request_oneshot

=cut

sub request_woosh { goto &woosh_request_oneshot; }

=head2 woosh_request_oneshot

    $murphx->woosh_request_oneshot( "service-id" => "12345", "fault-type" => "EPP",
        "has-worked" => "Y", "disruptive" => "Y", "fault-time" => "2007-01-04 15:33:00");

Places a request for  Woosh test to be run on the given service. Parameters are passed as
a hash which must contain:
    service-id - ID of the service
    fault-type - Type of fault to check. See Murphx documentation for available types
    has-worked - Y if the service has worked in the past, N if it has not
    disruptive - Y to allow Woosh to run a test which will be disruptive to the service.
    fault-time - date and time (ISO format) the fault occured

Returns a scalar which is the id of the woosh test. Use woosh_response with this id to get the results
of the Woosh test.

=cut

sub woosh_request_oneshot {
    my ($self, $args) = @_;
    for (qw/ service-id fault-type has-worked disruptive fault-time /) {
        if ( ! $args->{$_} ) { die "You must provide the $_ parameter"; }
    }

    my $response = $self->make_request("woosh_request_oneshot", $args);

    return $response->{a}->{"woosh-id"}->{content};
}

=head2 order_updates_since

    $murphx->order_updates_since( "2007-02-01 16:10:05" );

Alias to order_eventlog_changes

=cut

sub order_updates_since { goto &order_eventlog_changes; }

=head2 order_eventlog_changes

    $murphx->order_eventlog_changes( "2007-02-01 16:10:05" );

Returns a list of events that have occurred on all orders since the provided date/time.

The return is an date/time sorted array of hashes each of which contains the following fields:
    order-id date name value

=cut

sub order_eventlog_changes {
    my ($self, $time) = @_;
    return undef unless $time;

    my $response = $self->make_request("woosh_request_oneshot", {
        "date" => $time });

    my @updates = ();

    if ( ref $response->{block}->{block} eq "ARRAY" ) {
        while (my $b = shift @{$response->{block}->{block}} ) {
            my %a = ();
            foreach ( keys %{$b->{a}} ) {
                $a{$_}->$b->{a}->{$_}->{content};
            }
            push @updates, \%a;
        }
    } else {
        my %a = ();
        foreach (keys %{$response->{block}->{block}->{a}} ) {
            $a{$_} = $response->{block}->{block}->{a}->{$_}->{content};
        }
        push @updates, \%a;
    }
    return @updates;
}

=head2 auth_log

    $murphx->auth_log( "service-id" => '12345', "rows" => "5" );

Alias for service_auth_log

=cut

sub auth_log { goto &service_auth_log; }

=head2 service_auth_log

    $murphx->service_auth_log( "service-id" => '12345', "rows" => "5" );

Gets the last n rows, as specified in the rows parameter, of authentication log entries for the service

Returns an array, each element of which is a hash containing:
    auth-date, username, result and, if the login failed, error-message

=cut

sub service_auth_log {
    my ($self, $args) = @_;
    for (qw/service-id rows/) {
        if (!$args->{$_}) { die "You must provide the $_ parameter"; }
    }

    my $response = $self->make_request("service_auth_log", $args);

    my @auth = ();
    if ( ref $response->{block} eq "ARRAY" ) {
        while ( my $r = shift @{$response->{block}} ) {
            my %a = ();
            foreach ( keys %{$r->{block}->{a}} ) {
                $a{$_} = $r->{block}->{a}->{$_}->{content};
            }
            push @auth, \%a;
        }
    } else {
        my %a = ();
        foreach (keys %{$response->{block}->{block}->{a}} ) {
            $a{$_} = $r->{block}->{block}->{a}->{$_}->{content};
        }
        push @auth, \%a;
    }
    return @auth;
}

=head2 usage_summary 

    $murphx->usage_summary( '12345', '2009', '01' );

Alias for service_usage_summary()

=cut 

sub usage_summary { goto &service_usage_summary; }

=head2 service_usage_summary

    $murphx->service_usage_summary( "service-id" =>'12345', "year" => '2009', "month" => '01' );

Gets a summary of usage in the given month. Inputs are service-id, year, month.

Returns a hash with the following fields:
    year, month, username, total-sessions, total-session-time, total-input-octets,
    total-output-octets

Input octets are upload bandwidth. Output octets are download bandwidth.

Be warned that the total-input-octets and total-output-octets fields returned appear
to be MB rather than octets contrary to the Murphx documentation. 

=cut

sub service_usage_summary {
    my ($self, $args) = @_;
    for (qw/ service-id year month /) {
        if ( ! $args->{$_} ) { die "You must provide the $_ parameter"; }

    my $response = $self->make_request("service_usage_summary", $args);

    my %usage = ();
    foreach ( keys %{$response->{block}->{a}} ) {
        $usage{$_} = $response->{block}->{a}->{$_}->{content};
    }
    return %usage;
}

=head2 cease

    $murphx->cease( "service-id" => 12345, "reason" => "This service is no longer required"
        "client-ref" => "ABX129", "crd" => "1970-01-01", "accepts-charges" => 'Y' );

Places a cease order to terminate the ADSL service completely. Takes input as a hash.

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

    $murphx->requestmac( '12345', "EU wishes to change ISP" );

Obtains a MAC for the given service. Parameters are service-id and reason the customer
wants a MAC. 

Returns a hash comprising: mac, expiry-date

=cut

sub requestmac {
    my ($self, $args) = @_;
    for (qw/service-id reason/) {
        if (!$args->{$_}) { die "You must provide the $_ parameter"; }
        }

    my $response = $self->make_request("requestmac", $args);

    my %mac = ();

    $mac{mac} = $response->{a}->{mac}->{content};
    $mac{"expiry-date"} = $response->{a}->{"expiry-date"}->{content};

    return %mac;
}

=head2 service_history

    $murphx->service_history( "12345" );

Returns the full history for the given service as an array each element of which is a hash:
    order-id name date value

=cut

sub service_history { goto &service_eventlog_history; }

=head2 service_eventlog_history

$murphx->service_eventlog_history( "12345" );

Returns the full history for the given service as an array each element of which is a hash:
    order-id name date value

=cut

sub service_eventlog_history {
    my ($self, $service) = @_;
    return undef unless $service;

    my @history = ();

    if ( ref $response->{block}->{block} eq "ARRAY" ) {
        while ( my $a = pop @{$response->{block}->{block}} ) {
            my %a = ();
            foreach (keys %{$a->{a}}) {
                $a{$_} = $a->{'a'}->{$_}->{'content'};
            }
            push @history, \%a;
        }
    } else {
        my %a = ();
        foreach (keys $response->{block}->{block}->{a}) {
            $a{$_} = $response->{block}->{block}->{a}->{$_}->{'content'};
        }
        push @history, \%a;
    }
    return @history;
}

=head2 services_history

    $murphx->services_history( "start-date" => "2007-01-01", "stop-date" => "2007-02-01" );

Returns an array each element of which is a hash continaing the following data:
    service-id order-id date name value

=cut

sub services_history { goto &service_eventlog_changes; }

=head2 service_eventlog_changes

    $murphx->service_eventlog_changes( "start-date" => "2007-01-01", "stop-date" => "2007-02-01" );

Returns an array each element of which is a hash continaing the following data:
    service-id order-id date name value

=cut

sub service_eventlog_changes {
    my ($self, $args) = @_;
    for ( qw/ start-date stop-date /) {
        if (!$args->{$_}) { die "You must provide the $_ parameter"; }
    }

    my $response = $self->make_request("service_eventlog_changes", $args);

    my @changes = ();
    if ( ref $response->{block}->{block} eq 'ARRAY' ) {
        while ( my $a = shift @{$response->{block}->{block}} ) {
            my %u = ();
            foreach (keys %{$a->{a}}) {
                $u{$_} = $a->{'a'}->{$_}->{content};
            }
            push(@changes, \%u);
        }
    } else {
        my %u = ();
        foreach (keys $response->{block}->{block}->{a}) {
            $u{$_} = $response->{block}->{block}->{'a'}->{$_}->{content};
        }
        push(@changes, \%u);
    }
    return @changes;
}

sub order_history { goto &order_eventlog_history; }

=head2 order_eventlog_history
    
    $murphx->order_eventlog_history( '12345' );

Gets order history. Takes the order-id as input.

Returns an array, each element of which is a hash showing the next update in date
sorted order. The hash keys are date, name and value.

=cut

sub order_eventlog_history {
    my ($self, $order) = @_;
    return undef unless $order;
    my $response = $self->make_request("order_eventlog_history", { "order-id" => $order });

    my @history = ();

    if ( ref $response->{block}->{block} eq 'ARRAY' ) {
        while ( my $a = shift @{$response->{block}->{block}} ) {
            my %u = ();
            foreach (keys %{$a->{a}}) {
                $u{$_} = $a->{'a'}->{$_}->{content};
            }
            push(@history, \%u);
        }
    } else {
        my %u = ();
        foreach (keys $response->{block}->{block}->{a}) {
            $u{$_} = $response->{block}->{block}->{'a'}->{$_}->{content};
        }
        push(@history, \%u);
    }

    return @history;
}

=head2 order_status

    $murphx->order_status( '12345' );

Get's status of an order. Input is the order-id from Murphx

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

=head2 service_view

    $murphx->service_details ( '12345' );

Combines the data from service_details, service_history and service_options

Returns a hash as follows:

    &service = {    "service-details" => {
                        service-id => "", product-id => "", 
                        ... },
                    "service-options" => {
                        "speed-limit" => "", "suspended" => "",
                        ... },
                    ""service-history" => {
                        [ 
                            { "event-date" => "", ... },
                            ...
                        ] },
                    "customer-details" => {
                        "title" => "", "forename", ... }
                }

See Murphx documentation for full details

=cut

sub service_view {
    my ($self, $service) = @_;
    return undef unless $service;
    
    my $response = $self->make_request("service_details", {
            "service-id" => $service });

    my %service = ();
    foreach ( keys %{$response->{block}} ) {
        my $b = $_;
        if ( ref $response->{block}->{$b} eq "ARRAY" ) {
            my @history = ();
            while ( my $r = pop @{$response->{block}->{$b}->{block}} ) {
                my %a = ();
                foreach ( keys %{$r->{a}} ) {
                    $a{$_} = $r->{a}->{$_}->{content};
                }
                push @history, \%a;
            }
            $service{$b} = @history;
        } else {
            foreach ( keys %{$response->{block}->{$b}->{a}} ) {
                $service{$b}{$_} = $response->{block}->{$b}->{a}->{$_}->{content};
            }
        }
    }
    return %service;
}

=head2 service_details 

    $murphx->service_details( '12345' );

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
        for qw/fixed-ip routed-ip allocation-size hardware-product pstn-order-id
            max-interleaving test-mode inclusive-transfer mac losing-isp/;

    my $response = undef;
    if ( defined $data-in->{"mac"} && defined $data-in->{"losing-isp"} ) {
        $response = $self->make_request("migrate", $data);
    } else {
        $response = $self->make_request("provide", $data);
    }

    my %order = ();
    foreach ( keys %{$response->{a}} ) {
        $order{$_} = $response->{a}->{$_}->{content};
    }
    return %order;
}

1;
