package Net::DSLProvider::Enta;
use HTML::Entities qw(encode_entities_numeric);
use base 'Net::DSLProvider';
use constant ENDPOINT => "https://partners.enta.net/";
use constant BOUNDARY => "abc123xyz890";
use constant REALM => "Entanet Partner Logon";
use LWP;
use HTTP::Cookies;
use IO::File;
use POSIX;
use XML::Simple;
use Time::Piece;
use Time::Seconds;

# These are methods for which we have to pass Enta a block of XML as a file
# via POST rather than simply using GET with the parameters and the fields 
# in the XML are case sensitive while they are not when using GET
my @xml_methods = ("AdslProductChange", "ModifyLineFeatures", 
    "UpdateADSLContact", "CreateADSLOrder");
my $xml_methods = join("|", @xml_methods);

my @stupidEnta = ("CreateADSLOrder", "AdslProductChange", 
    "ModifyLineFeatures", "UpdateADSLContact");
my $stupidlist = join("|", @stupidEnta);

my %formats = (
    AdslAccount => { "" => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" }},
    ListConnections => { "" => { "liveorceased" => "text", "fields" => "text" }},
    CheckUsernameAvailable => { "" => { "Username" => "text" }},
    GetBTFault => { "" => { "day" => "text", "start" => "text", "end" => "text" }},
    GetAdslInstall => { "" => { "Username" => "text", "Ref" = "text" }},
    GetBTFeed => { "" => { "days" => "counting" }},
    GetNotes => => { "" => { "Username" => "text", "Ref" = "text" }},
    PendingOrders => { "" => { }},
    PSTNPendingOrders => { "" => { }},
    LastRadiusLog => { "" => { "Username" => "text", "Ref" = "text" }},
    ConnectionHistory => { "" => { "Username" => "text", "Ref" = "text", "Telephone" => "phone", 
        "days" => "counting" }},
    GetInterleaving => { "" => { "Username" => "text", "Ref" = "text", "Telephone" => "phone" }},
    GetOpenADSLFaults => { "" => { "Username" => "text", "Ref" = "text", "Telephone" => "phone" }},
    RequestMAC => { "" => { "" => { "Username" => "text", "Ref" = "text", "Telephone" => "phone" }},
    UsageHistory => { "" => { "Username" => "text", "Ref" = "text", "Telephone" => "phone",
        "starttimestamp" = "unixtime", "endtimestamp" => "unixtime", "rawdisplay" => "text",
        "startdatetime" => "dd/mm/yyyy hh:mm:ss", "enddatetime" => "dd/mm/yyyy hh:mm:ss" }},
    UsageHistoryDetail => { "" => { "Username" => "text", "Ref" => "text", "Telephone" => "phone",
        "startday" => "dd/mm/yyyy", "endday" => "dd/mm/yyyy", "day" => "dd/mm/yyyy" }},
    GetMaxReports => { "" => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" }},
    CreateADSLOrder => { 
        ADSLAccount => {
            "YourRef" => "client-ref", "Product" => "prod-id", "MAC" => "mac",
            "Title" => "title", "FirstName" => "forename", 
            "Surname" => "surname", "CompanyName" => "company",
            "Building" => "building", "Street" => "street", "Town" => "city",
            "County" => "county", "Postcode" => "postcode", 
            "TelephoneDay" => "telephone", "TelephoneEvening" => "telephone",
            "Fax" => "fax", "Email" => "email", "Telephone" => "cli",
            "ProvisionDate" =>"crd", "NAT" => "routed-ip", 
            "Username" => "username", "Password" => "password",
            "LineSpeed" => "linespeed", "OveruseMethod" => "topup",
            "ISPName" => "losing-isp", "CareLevel" => "care-level",
            "Interleave" => "max-interleaving", "ForceLowerSpeed" = "classic",
            "BTProductSpeed" => "classic-speed", "Realm" => "realm",
            "BaseDomain" => "realm", "ISDN" => "isdn",
            "InitialCareLevelFee" => "iclfee", 
            "OngoingCareLevelFee" => "oclfee", "TagOnTheLine" => 'totl',
            "MaxPAYGAmount" => "payg-limit" 
        }
        CustomerRecord => {
            "cCustomerID" => "customer-id", "cTtitle" => "ctitle",
            "cFirstName" => "cforename", "cSurname" => "csurname",
            "cCompanyName" => "ccompany", "cBuilding" => "cbuilding",
            "cStreet" => "cstreet", "cTown" => "ctown", 
            "cCounty" => "ccounty", "cPostcode" => "cpostcode",
            "cTelephoneDay" => "ctelephone", 
            "cTelephoneEvening" => "ctelephone",
            "cFax" => "cfax", "cEmail" => "cemail"
        }
        BillingAccount => {
            "PurchaseOrderNumber" => "client-ref", 
            "BillingPeriod" => "billing-period", 
            "ContractTerm" => "contract-term",
            "InitialPaymentMethod" => "initial-payment",
            "OngoingPaymentMethod" => "ongoing-payment",
            "PaymentMethod" => "payment-method" 
        }
    },
    AdslProductChange => { 
        (map "ProductChange " . $_ => {
            NewProduct => {
                Family => "text", Speed => "text", Cap => "counting"
            },
            Schedule => "text"
        } qw/Username Ref/) 
    },
    ModifyLineFeatures => { "ADSLAccount" => {
        "Ref" => "text", "Username" => "text", "Telephone" => "phone",
        "LineFeatures" = > {
            "Interleaving" => "text", "StabilityOption" => "text", 
            "ElevatedBestEfforts" => "yesno", "ElevatedBestEffortsFee" => "text", 
            "MaintenanceCategory" => "counting", "MaintenanceCategoryFee" => "text"
            }
        }
    },
    CeaseADSLOrder => { "" => { "Username" => "text", "Ref" => "text", "Telephone" => "phone", 
        CeaseDate => 'dd/mm/yyyy' }},
    ChangeInterleave => { "" => { "Username" => "text", "Ref" => "text", "Telephone" => "phone",
        Interleave => "text" }},
    UpdateADSLContact => { "" => { "Ref" => "text", "Username" => "text", Telephone => "phone",
        ContactDetails => { Email => "email", TelDay => "phone", TelEve => "phone" } 
        }
    }
);


sub request_xml {
    my ($self, $method, $data) = @_;

    my $live = "Live";
    $live = "Test" if @{[$self->testing]};

    my $stupidEnta = 1 if $method =~ /($stupidlist)/;

    my $xml = qq|<?xml version="1.0" encoding="UTF-8"?>
    <ResponseBlock Type="$live">|;
    if ( $stupidEnta ) {
        $xml .= qq|<Response Type="$method">
        <OperationResponse Type="$method">|;
    } else {
        $xml .= qq|<OperationResponse Type="$method">|;
    }

    my $recurse;
    $recurse = sub {
        my ($format, $data) = @_;
        while (my ($key, $contents) = each %$format) {
            if (ref $contents eq "HASH") {
                if ($key) { $xml .= "<$key>\n"; }
                $recurse->($contents, $data->{$key});
                if ($key) { $xml .= "</$key>\n"; }
            } else {
                $xml .= qq{<$key>}.encode_entities_numeric($data->{$key})."</$key>\n" if $data->{$key};
            }
        }
    };
    $recurse->($formats{$method}, $data); 

    if ( $stupidEnta ) {
        $xml .= "</OperationResponse>\n</Response>\n</ResponseBlock>";
    } else {
        $xml .= "</OperationResponse>\n</ResponseBlock>";
    }
    return $xml;
}

sub make_request {
    my ($self, $method, $data) = @_;

    my $ua = new LWP::UserAgent;
    my ($req, $res);
    $ua->cookie_jar({});
    my $agent = __PACKAGE__ . '/0.1 ';
    $ua->agent($agent . $ua->agent);

    my $url = ENDPOINT . $method . '.php?';
    if ( $method =~ /($xml_methods)/ ) {     
        push @{$ua->requests_redirectable}, 'POST';
        my $xml = $self->request_xml($method, $data);

        my $body .= "--" . BOUNDARY . "\n";
        $body .= "Content-Disposition: form-data; name=\"userfile\"; filename=\"XML.data\"\n";
        $body .= "Content-Type: application/octet-stream\n\n";
        $body .= $xml;
        $body .= "\n";
        $body .= "--" . BOUNDARY . "--\n";

        $req = new HTTP::Request 'POST' => $url;
    } else {
        push @{$ua->requests_redirectable}, 'GET';
        $url .= "$key=$value&" while (($key, $value) = each (%args));
        $req = new HTTP::Request 'GET' => $url;
    }

    $req->authorization_basic(@{[$self->user]}, @{[$self->pass]});
    $req->header( 'MIME_Version' => '1.0', 'Accept' => 'text/xml' );

    if ( $method =~ /( )/ ) {
        $req->header('Content-type' => 'multipart/form-data; type="text/xml"; boundary=' . $boundary);
        $req->header('Content-length' => length $body);
        $req->content($body);
    }

    $res = $ua->request($req);

    die "Request for Enta method $method failed: " . $res->message if $res->is_error;
    my $resp_o = XMLin($res->content);

    if ($resp_o->{Response}{Type} eq 'Error') { die  $resp_o->{OperationResponse}{ErrorDescription} };
    return $resp_o;
}

sub convert_input {
    my ($self, $method, $args) = @_;
    die unless $method && ref $args eq 'HASH';

    my $data = {};

    foreach ( keys %{$formats{$method}} ) {
        if ( ref $formats{$method}->{$_} eq "HASH" ) {
            my $k = $_;
            foreach ( keys %{$formats{$method}{$k}} ) {
                $data->{$k}->{$_} = $args->{$formats{$method}{$k}{$_}};
            }
        }
        else {
            $data->{$_} = $args->{$formats{$method}->{$_}};
        }
    }
    return $data;
}

sub serviceid {
    # used internally only to get the correct service identifier to 
    # present to Enta
    my ( $self, $args ) = @_;
    die unless ($args->{"ref"} || $args->{"username"} || 
        $args->{"telephone"} || $args->{"service-id"} ||
        $args->{"order-id"} );

    return { "Ref" => $args->{"service-id"} } if $args->{"service-id"};
    return { "Ref" => $args->{"order-id"} } if $args->{"order-id"};
    return { "Ref" => $args->{"ref"} } if $args->{"ref"};
    return { "Username" => $args->{"username"} } if $args->{"username"};
    return { "Telephone" => $args->{"telephone"} } if $args->{"telephone"};
}

sub services_available {
    my ($self, $args) = @_;

    return { "" => "" };
}

=head2 line_check
    
    $enta->line_check( cli => '02072221111', mac => 'ABCD123456/XY12Z' );

Given a cli and, optionally, a MAC line_check will determine whether it is
possible to provide DSL service on the line and if given a MAC it will 
determine whether the MAC is valid.

Returns details of which services are available and sets mac-valid to 1
if the MAC is valid.

=cut

sub line_check {
    my ($self, $args) = @_;
    die "You must provide the cli parameter" unless $args->{cli};

    my %data = ();
    $data->{PhoneNo} = $args->{cli};
    $data->{MAC} = $args->{mac} if $args->{mac};

    my $response = $self->make_request("ADSLChecker", $data);

    my %result = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}} ) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq "HASH" ) {
            my $h = $_;
            foreach ( %{$response->{Response}->{OperationResponse}->{$h}} ) {
                $results{$h}{$_} = $response->{Response}->{OperationResponse}->{$h}->{$_};
            }
        }
        $results{$_} = $response->{Response}->{OperationResponse}->{$_};
    }
    return %result;
}

=head2 verify_mac

    $enta->verify_mac( cli => "02072221111", mac => "ABCD0123456/ZY21X" );

Given a cli and MAC returns 1 if the MAC is valid.

=cut

sub verify_mac {
    my ($self, $args) = @_;
    for (qw/cli mac/) {
        die "You must provide the $_ parameter" unless $args->{$_};
    }

    my %line = $self->line_check( { 
        "cli" => $args->{cli}, 
        "mac" => $args->{mac} 
        } );
    
    return undef unless $line->{MAC}->{Valid};
    return 1;
}

=head2 interleaving

    $enta->interleaving( "service-id" => "ADSL123456", "interleaving" => "No")

Changes the interleaving setting on the given service

=cut

sub interleaving {
    my ($self, $args) = @_;
    die "You must provide the Interleaving parameter plus service identifier"
        unless $args->{interleaving} && ( $args->{ref} || $args->{username}
        || $args->{telephone} );

    die "interleaving can only be 'Yes', 'No' or 'Auto'" unless
        $args->{option} =~ /(Yes|No|Auto)/;

    my $serviceId = $self->serviceid($args);

    return $self->modifylinefeatures( { %$serviceId,  "LineFeatures" => { 
        "Interleaving" => $args->{interleaving} } });
}

=head2 stabilityoption 

    $enta->stabilityoption( "service-id" => "ADSL123456", "option" => "Standard" );

Sets the Stability Option feature on a service

=cut

sub stabilityoption {
    my ($self, $args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args->{"option"} && ( $args->{ref} || $args->{username}
        || $args->{telephone} );

    die "option can only be 'Standard', 'Stable', or 'Super Stable'" unless
        $args->{option} =~ /(Standard|Stable|Super Stable)/;

    my $serviceId = $self->serviceid($args);

    return $self->modifylinefeatures( { %$serviceId,  "LineFeatures" => {
        "StabilityOption" => $args->{"option"} } } );
}

=head2 elevatedbestefforts

    $enta->elevatedbestefforts( "service-id" => "ADSL123456", "option" => "Yes",
        "fee" => "5.00" );

Enables or disables Elevated Best Efforts on the given service. If the
optional "fee" parameter is passed the monthly fee for this option is 
set accordingly, otherwise it is set to the default charged by Enta.

=cut

sub elevatedbestefforts {
    my ($self, $args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args->{"option"} && ( $args->{ref} || $args->{username}
        || $args->{telephone} );

    die "option can only be 'Yes' or 'No'" unless
        $args->{option} =~ /(Yes|No)/;

    my $serviceId = $self->serviceid($args);

    my $data = { "LineFeatures" => { 
        "ElevatedBestEfforts" => $args->{"option"} } };

    $data->{"LineFeatures"}{"ElevatedBestEffortsFee"} = $args->{"fee"}
        if $args->{"fee"};

    return $self->modifylinefeatures( { %$serviceId,  %$data } );
}

=head2 enhancedcare
    
    $enta->enhancedcare( "service-id" => "ADSL123456", "option" => "On",
        "fee" => "15.00" );

Enables or disabled Enhanced Care on a given service. If the optional
"fee" parameter is passed the monthly fee for this option is set 
accordingly, otherwise it is set to the default charged by Enta.

=cut

sub enhancedcare {
    my ($self, $args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args->{"option"} && ( $args->{ref} || $args->{username}
        || $args->{telephone} );

    die "option can only be 'On' or 'Off'" unless
        $args->{option} =~ /(On|Off)/;

    my $serviceId = $self->serviceid($args);
    my $ec = 4 if $args->{option} eq 'On';
    my $ec = 5 if $args->{option} eq 'Off';

    my $data = { "LineFeatures" => {
        "MaintenanceCategory" => $ec }};

    $data->{"LineFeatures"}{"MaintenanceCategoryFee"} = $args->{"fee"}
        if $args->{"fee"};

    return $self->modifylinefeatures( { %$serviceId,  %$data });
}

=head2 modifylinefeatures

    $enta->modifylinefeatures(
        "Ref" => "ADSL123456", "Username" => "abcdef", 
        "Telephone" => "02071112222", "LineFeatures" => {
            "Interleaving" => "No", 
            "StabilityOption" => "Standard", 
            "ElevatedBestEfforts" => "Yes", 
            "ElevatedBestEffortsFee" => "15.00", 
            "MaintenanceCategory" => "4",
            "MaintenanceCategoryFee" => "25.00"
        } );

Modify the Enta service reference specificed in either Ref, Username or
Telephone. Parameters are as per the Enta documentation

Returns a hash containing details of the new settings resulting from the 
change(s) made - ie:

    %return = { interleaving => "No" };

=cut

sub modifylinefeatures {
    my ($self, $args) = @_;
    die "You must provide the LineFeatures parameter plus service identifier"
        unless $args->{LineFeatures} && 
            ( $args->{ref} || $args->{username} || $args->{telephone} );

    my $response = $self->make_request("ModifyLineFeatures", $args);

    my %return = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}} ) {
        $return{$_} = $response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}->{$_}->{NewValue};
    }
    return %return;
}

=head2 order_updates_since

    $enta->order_updates_since( "date" => "2009-12-01 00:01:01" );

Returns all the BT order updates since the given date

=cut

sub order_updates_since { 
    my ($self, $args) = @_;
    die "You must provide the date parameter" unless $args->{"date"};

    my $from = Time::Piece->strptime($args->{"date"}, "%F");
    my $now = localtime;

    my $d = $now - $from;
    my $days = $d->days;
    $days =~ s/\.\d+//;
    return &getbtfeed( "days" => $days );
}

=head2 getbtfeed

    $enta->getbtfeed( "days" => "5" );

Returns a list of events that have occurred on all orders since the provided date/time.

The return is an date/time sorted array of hashes each of which contains the following fields:
    order-id date name value

=cut

sub getbtfeed {
    my ($self, $args) = @_;
    die "You must provide the days parameter" unless $args->{"days"};

    my $response = $self->make_request("GetBTFeed", $args);

    my @records = ();
    while ( my $r = pop @{$response->{Response}->{OperationResponse}->{Records}->{Record}} ) {
        my %a = ();
        foreach (keys %{$r}) {
            if ( ref $r->{$_} eq 'HASH' ) {
                my $b = $_;
                foreach (keys %{$r->{$b}} ) {
                     $a{$b}{$_} = $r->{$b}->{$_};
                }
                next;
            }
            $a{$_} = $r->{$_};
        }
        push @records, \%a;
    }
    return { "updates" => @records };
}


=head2 usage_summary 

    $enta->usage_summary( "service-id" => "ADSL12345", "year" => '2009', "month" => '01' );

=cut 

sub usage_summary {
    my ($self, $args) = @_;
    for (qw/service-id year month/) {
    die "You must provide the $_ parameter" unless $args->{$_}
    }

    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("", { %$serviceid, %$args } );
}

=head2 usagehistory 

    $enta->usagehistory( "service-id" =>'ADSL12345' );

Gets a summary of usage for the given service. Optionally a start and end
date for the query may be specified either as a unix timestamp, in which
case the parameters are StartTimestamp and EndTimestamp, or in 
"dd/mm/yyyy hh:mm:ss" format, in which case the parameters are 
StartDateTime and EndDateTime

Returns a hash with the following fields:
    
    year, month, username, total-sessions, total-session-time, total-input-octets,
    total-output-octets

Input octets are upload bandwidth. Output octets are download bandwidth.

Be warned that the total-input-octets and total-output-octets fields returned appear
to be MB rather than octets contrary to the Murphx documentation. 

=cut

sub usagehistory {
    my ($self, $args) = @_;
    die "You must provide the service-id parameter" 
        unless $args->{"service-id"};

    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("", { %$serviceid, %$args } );
    
}

=head2 cease

    $enta->cease( "service-id" => "ADSL12345", "crd" => "1970-01-01" );

Places a cease order to terminate the ADSL service completely. 

=cut

sub cease {
    my ($self, $args) = @_;
    for (qw/service-id crd/) {
    die "You must provide the $_ parameter" unless $args->{$_}

    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("", { %$serviceid, %$args } );
    
}

=head2 requestmac

    $murphx->requestmac( "service-id" => 'ADSL12345');

Obtains a MAC for the given service. 

Returns a hash comprising: mac, expiry-date if the MAC is available or
submits a request for the MAC which can be obtained later.

=cut

sub requestmac {
    my ($self, $args) = @_;
    die "You must provide the service-id parameter" 
        unless $args->{"service-id"};

    my $adsl = $self->adslaccount($args);
    if ( $adsl->{"ADSLAccount"}->{"MAC"} ) {
        my $expires = $adsl->{"ADSLAccount"}->{"MACExpires"};
        $expires =~ s/\+\d+//;
        return { "mac" => $adsl->{"ADSLAccount"}->{"MAC"},
                 "expiry-date" => $expires };
    }

    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("RequestMAC", $serviceid );

    return { "Requested" => 1 };
}

=head2 service_view

    $enta->service_details( "service-id" => 'ADSL12345' );

Returns the ADSL service details

=cut

sub service_view { goto &adslaccount; }

=head2 service_details 

    $enta->service_details( "service-id" => 'ADSL12345' );

Returns the ADSL service details

=cut

sub service_details { goto &adslaccount; }

=head2 adslaccount

    $enta->adslaccount( "service-id" => "ADSL12345" );

Returns details for the given service

=cut

sub adslaccount {
    my ($self, $args) = @_;
    die "You must provide the service-id parameter" 
        unless $args->{"service-id"};
    
    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("AdslAccount", $serviceid );

    my %data = ();
    foreach (keys %{$response->{Response}->{OperationResponse}} ) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq 'HASH' ) {
            my $b = $_;
            foreach (keys %{$response->{Response}->{OperationResponse}->{$b}} {
                $data{$b}{$_} = $response->{Response}->{OperationResponse}->{$b}->{$_};
            }
        } else {
            $data{$_} = $response->{Response}->{OperationResponse}->{$_};
        }
    }
    return %data;
}

=head2 auth_log

    $enta->auth_log( "service-id" => 'ADSL12345' );

Gets the most recent authentication attempt log

=cut

sub auth_log {
    my ($self, $args) = @_;
    die "You must provide the service-id parameter" 
        unless $args->{"service-id"};

    my $serviceId = $self->serviceid($args);
    
    my $response = $self->make_request("LastRadiusLog", $serviceid );

    my %log = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}} ) {
        $log{$_} = $response->{Response}->{OperationResponse}->{$_};
    }
    return %log;
}

=head2 order

    $enta->order(
        # Customer details
        forename => "Clara", surname => "Trucker", company => "ABC Ltd",
        building => "123", street => "Pigeon Street", city => "Manchester", 
        county => "Greater Manchester", postcode => "M1 2JX",
        telephone => "01614960213", email => "clare@example.com",
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
been supplied to you by Enta.

Additional parameters are listed below and described in the integration
guide:

    title street company mobile email fax sub-premise fixed-ip routed-ip
    allocation-size hardware-product max-interleaving test-mode
    inclusive-transfer

=cut

sub order {
    my ($self, $args) = @_;
    for (qw/prod-id title forename surname street city county postcode
        telephone email cli crd routed-ip username password linespeed
        topup care-level billing-period contract-term initial-payment 
        ongoing-payment payment-method mac totl max-interleaving 
        customer-id/) {
        die "You must provide the $_ parameter" unless $args->{$_};
    }

    if ( $args->{"customer-id"} eq 'New' ) {
        for (qw/ctitle cforename csurname cstreet ctown ccounty cpostcode
            ctelephone cemail/) {
            die "You must provide the $_ parameter" unless $args->{$_};
        }
    }

    $args->{"isdn"} = 'N';

    my $data = $self->convert_input("CreateADSLOrder", $args);

    my $response = $self->make_request("CreateADSLOrder", $data);

    return { "order-id" => $response->{Response}->{OperationResponse}->{OurRef},
             "service-id" => $response->{Response}->{OperationResponse}->{OurRef} };
}

1;
