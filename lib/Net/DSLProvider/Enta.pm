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
    AdslAccount => { "" => { "username" => "text", "ref" => "text", "telephone" => "phone" }},
    ListConnections => { "" => { "liveorceased" => "text", "fields" => "text" }},
    CheckUsernameAvailable => { "" => { "username" => "text" }},
    GetBTFault => { "" => { "day" => "text", "start" => "text", "end" => "text" }},
    GetAdslInstall => { "" => { "username" => "text", "ref" = "text" }},
    GetBTFeed => { "" => { "days" => "counting" }},
    GetNotes => => { "" => { "username" => "text", "ref" = "text" }},
    PendingOrders => { "" => { }},
    PSTNPendingOrders => { "" => { }},
    LastRadiusLog => { "" => { "username" => "text", "ref" = "text" }},
    ConnectionHistory => { "" => { "username" => "text", "ref" = "text", "telephone" => "phone", 
        "days" => "counting" }},
    GetInterleaving => { "" => { "username" => "text", "ref" = "text", "telephone" => "phone" }},
    GetOpenADSLFaults => { "" => { "username" => "text", "ref" = "text", "telephone" => "phone" }},
    RequestMAC => { "" => { "" => { "username" => "text", "ref" = "text", "telephone" => "phone" }},
    UsageHistory => { "" => { "username" => "text", "ref" = "text", "rawdisplay" => "text",
        "starttimestamp" = "unixtime", "endtimestamp" => "unixtime", 
        "startdatetime" => "dd/mm/yyyy hh:mm:ss", "enddatetime" => "dd/mm/yyyy hh:mm:ss" }},
    UsageHistoryDetail => { "" => { "username" => "text", "ref" = "text", "day" => "dd/mm/yyyy",
        "startday" => "dd/mm/yyyy", "endday" => "dd/mm/yyyy" }},
    GetMaxReports => { "" => { "username" => "text", "ref" = "text" }},
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
    CeaseADSLOrder => { "" => { "Ref" => "text", "Username" => "text", 
        CeaseDate => 'dd/mm/yyyy' }},
    ChangeInterleave => { "" => { "Ref" => "text", "Username" => "text",
        Interleave => "text" }},
    UpdateADSLContact => { "" => { "Ref" => "text", "Username" => "text", Telephone => "phone",
        ContactDetails => { Email => "email", TelDay => "phone", TelEve => "phone" } 
        }
    }
);


sub request_xml {
    my ($self, $method, $data) = @_;

    my $live = "Live";
    $live = "Test" if defined $self->testing;

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
        while (my ($key, $contents) = each %$formats) {
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

        my $body .= "--$boundary\n";
        $body .= "Content-Disposition: form-data; name=\"userfile\"; filename=\"XML.data\"\n";
        $body .= "Content-Type: application/octet-stream\n\n";
        $body .= $xml;
        $body .= "\n";
        $body .= "--$boundary--\n";

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

sub serviceid {
    # used internally only to get the correct service identifier to 
    # present to Enta
    my ( $self, $args ) = @_;
    die unless ($args->{ref} || $args->{username} || $args->{telephone});

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

=head interleaving

    $enta->interleaving( "ref" => "ADSL123456", "interleaving" => "No")

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

=head stabilityoption 

    $enta->stabilityoption( ref => "ADSL123456", "option" => "Standard" );

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

=head elevatedbestefforts

    $enta->elevatedbestefforts( ref => "ADSL123456", "option" => "Yes",
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
    
    $enta->enhancedcare( ref => "ADSL123456", "option" => "On",
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
    return undef unless $args->{"date"};

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
    return undef unless $args->{"days"};

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

    $enta->usage_summary( "ref" => "ADSL12345", "year" => '2009', "month" => '01' );

=cut 

sub usage_summary {
    my ($self, $args) = @_;

}

=head2 usagehistory 

    $enta->usagehistory( "ref" =>'ADSL12345' );

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

}

=head2 cease

    $enta->cease( "ref" => "ADSL12345", "crd" => "1970-01-01" );

Places a cease order to terminate the ADSL service completely. 

=cut

sub cease {
    my ($self, $args) = @_;

}

=head2 requestmac

    $murphx->requestmac( "ref" => 'ADSL12345');

Obtains a MAC for the given service. 

Returns a hash comprising: mac, expiry-date

=cut

sub requestmac {
    my ($self, $args) = @_;


}

}


=head2 service_view

    $enta->service_details( "ref" => 'ADSL12345' );

Returns the ADSL service details

=cut

sub service_view { goto &adslaccount; }

=head2 service_details 

    $enta->service_details( "ref" => 'ADSL12345' );

Returns the ADSL service details

=cut

sub service_details { goto &adslaccount; }

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
    for (qw/ list all mandatory parameters here /) {
        die "You must provide the $_ parameter" unless $args->{$_};
    }

    my $data = {};

    foreach ( keys %{$formats{"CreateADSLOrder"}} ) {
        if ( ref $formats{"CreateADSLOrder"}->{$_} eq "HASH" ) {
            my $k = $_;
            foreach ( keys %{$formats{"CreateADSLOrder"}{$k}} ) {
                $data->{$k}->{$_} = $args->{$formats{"CreateADSLOrder"}{$k}{$_}};
            }
        }
        else {
            $data->{$_} = $args->{$formats{"CreateADSLOrder"}->{$_}};
        }
    }

    my $response = $self->make_request("CreateADSLOrder", $data);

    return { "order-id" => $response->{Response}->{OperationResponse}->{OurRef},
             "service-id" => $response->{Response}->{OperationResponse}->{OurRef} };
}

=head2 auth_log

    $enta->auth_log( "Ref" => 'ADSL12345' );

Gets the most recent authentication attempt log

=cut

sub auth_log {
    my ($self, $args) = @_;

}

1;
