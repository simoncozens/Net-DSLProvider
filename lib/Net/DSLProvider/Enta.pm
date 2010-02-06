package Net::DSLProvider::Enta;
use strict;
use warnings;
use HTML::Entities qw(encode_entities_numeric);
use base 'Net::DSLProvider';
use constant ENDPOINT => "https://partners.enta.net/";
use constant BOUNDARY => "abc123xyz890";
use constant REALM => "Entanet Partner Logon";
use LWP;
use HTTP::Cookies;
use IO::File;
#use POSIX;
use XML::Simple;
use Time::Piece;
use Time::Seconds;

# These are methods for which we have to pass Enta a block of XML as a file
# via POST rather than simply using GET with the parameters and the fields 
# in the XML are case sensitive while they are not when using GET

my %enta_xml_methods = ( "AdslProductChange" => 1, 
    "ModifyLineFeatures" => 1, "UpdateADSLContact" => 1,
    "CreateADSLOrder" => 1 );

my %entatype = ( "CreateADSLOrder" => "ADSLOrder",
    "ModifyLineFeatures" => "ModifyLineFeatures",
    "UpdateADSLContact" => "UpdateADSLContact",
    "AdslProductChange" => "AdslProductChange" );

my %formats = (
    ADSLChecker => { "PhoneNo" => "phone", "Version" => "4",
        "MACcode" => "text" },
    AdslAccount => { "Username" => "username", "Ref" => "ref", "Telephone" => "telephone" },
    ListConnections => { "liveorceased" => "text", "fields" => "text" },
    CheckUsernameAvailable => { "Username" => "username" },
    GetBTFault => { "day" => "text", "start" => "text", "end" => "text" },
    GetAdslInstall => { "Username" => "text", "Ref" => "text" },
    GetBTFeed => { "days" => "counting" },
    GetNotes => => { "Username" => "text", "Ref" => "text" },
    LastRadiusLog => { "Username" => "text", "Ref" => "text" },
    ConnectionHistory => { "Username" => "text", "Ref" => "text", "Telephone" => "phone", 
        "days" => "counting" },
    GetInterleaving => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    GetOpenADSLFaults => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    RequestMAC => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    UsageHistory => { "Username" => "text", "Ref" => "text", "Telephone" => "phone",
        "starttimestamp" => "unixtime", "endtimestamp" => "unixtime", "rawdisplay" => "text",
        "startdatetime" => "dd/mm/yyyy hh:mm:ss", "enddatetime" => "dd/mm/yyyy hh:mm:ss" },
    UsageHistoryDetail => { "Username" => "text", "Ref" => "text", "Telephone" => "phone",
        "startday" => "dd/mm/yyyy", "endday" => "dd/mm/yyyy", "day" => "dd/mm/yyyy" },
    GetMaxReports => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    CreateADSLOrder => { 
        ADSLAccount => {
            "YourRef" => "client-ref", "Product" => "prod-id", "MAC" => "mac",
            "Title" => "title", "FirstName" => "forename", 
            "Surname" => "surname", "CompanyName" => "company",
            "Building" => "building", "Street" => "street", "Town" => "city",
            "County" => "county", "Postcode" => "postcode", 
            "TelephoneDay" => "telephone", "TelephoneEvening" => "telephone",
            "Fax" => "fax", "Email" => "email", "Telephone" => "cli",
            "ProvisionDate" =>"crd", "NAT" => "allocation-size", 
            "Username" => "username", "Password" => "password",
            "LineSpeed" => "linespeed", "OveruseMethod" => "topup",
            "ISPName" => "losing-isp", "CareLevel" => "care-level",
            "Interleave" => "max-interleaving", "ForceLowerSpeed" => "classic",
            "BTProductSpeed" => "classic-speed", "Realm" => "realm",
            "BaseDomain" => "realm", "ISDN" => "isdn",
            "InitialCareLevelFee" => "iclfee", 
            "OngoingCareLevelFee" => "oclfee", "TagOnTheLine" => 'totl',
            "MaxPAYGAmount" => "payg-limit" 
        },
        CustomerRecord => {
            "cCustomerID" => "customer-id", "cTitle" => "ctitle",
            "cFirstName" => "cforename", "cSurname" => "csurname",
            "cCompanyName" => "ccompany", "cBuilding" => "cbuilding",
            "cStreet" => "cstreet", "cTown" => "ctown", 
            "cCounty" => "ccounty", "cPostcode" => "cpostcode",
            "cTelephoneDay" => "ctelephone", 
            "cTelephoneEvening" => "ctelephone",
            "cFax" => "cfax", "cEmail" => "cemail"
        },
        BillingAccount => {
            "PurchaseOrderNumber" => "client-ref", 
            "BillingPeriod" => "billing-period", 
            "ContractTerm" => "contract-term",
            "InitialPaymentMethod" => "initial-payment",
            "OngoingPaymentMethod" => "ongoing-payment",
            "PaymentMethod" => "payment-method" 
        }
    },
    ModifyLineFeatures => { "ADSLAccount" => {
        "Ref" => "text", "Username" => "text", "Telephone" => "phone",
        "LineFeatures" => {
            "Interleaving" => "text", "StabilityOption" => "text", 
            "ElevatedBestEfforts" => "yesno", "ElevatedBestEffortsFee" => "text", 
            "MaintenanceCategory" => "counting", "MaintenanceCategoryFee" => "text"
            }
        }
    },
    CeaseADSLOrder => { "Username" => "text", "Ref" => "text", "Telephone" => "phone", 
        CeaseDate => 'dd/mm/yyyy' },
    ChangeInterleave => { "Username" => "text", "Ref" => "text", "Telephone" => "phone",
        Interleave => "text" },
    UpdateADSLContact => { "Ref" => "ref", "Username" => "username", Telephone => "telephone",
        ContactDetails => { Email => "email", TelDay => "phone", TelEve => "phone" } 
    } );


sub request_xml {
    my ($self, $method, $data) = @_;

    my $live = "Live";
    $live = "Test" if @{[$self->testing]};

    my $stupidEnta = 1 if $enta_xml_methods{$method};

    my $xml = qq|<?xml version="1.0" encoding="UTF-8"?>
    <ResponseBlock Type="$live">\n|;
    if ( $stupidEnta ) {
        $xml .= qq|<Response Type="| . $entatype{$method} . qq|">
        <OperationResponse Type="| . $entatype{$method} . qq|">\n|;
    } else {
        $xml .= qq|<OperationResponse Type="| . $entatype{$method} . qq|">\n|;
    }

    my $recurse;
    $recurse = sub {
        my ($format, $data) = @_;
        while (my ($key, $contents) = each %$format) {
            if (ref $contents eq "HASH") {
                if ($key) { $xml .= "\t<$key>\n"; }
                $recurse->($contents, $data->{$key});
                if ($key) { $xml .= "</$key>\n"; }
            } else {
                $xml .= qq{\t\t<$key>}.encode_entities_numeric($data->{$key})."</$key>\n" if $data->{$key};
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
    my ($req, $res, $body) = ();
    $ua->cookie_jar({});
    my $agent = __PACKAGE__ . '/0.1 ';
    $ua->agent($agent . $ua->agent);

    my $url = ENDPOINT . "xml/$method" . '.php';
    if ( $enta_xml_methods{$method} ) {     
        push @{$ua->requests_redirectable}, 'POST';
        my $xml = $self->request_xml($method, $data);

        $body .= "--" . BOUNDARY . "\n";
        $body .= "Content-Disposition: form-data; name=\"userfile\"; filename=\"XML.data\"\n";
        $body .= "Content-Type: application/octet-stream\n\n";
        $body .= $xml;
        $body .= "\n";
        $body .= "--" . BOUNDARY . "--\n";

        $req = new HTTP::Request 'POST' => $url;
    } else {
        push @{$ua->requests_redirectable}, 'GET';
        my ($key, $value);
        $url .= '?';
        $url .= "$key=$value&" while (($key, $value) = each (%$data));

        $req = new HTTP::Request 'GET' => $url;
    }

    $req->authorization_basic(@{[$self->user]}, @{[$self->pass]});
    $req->header( 'MIME_Version' => '1.0', 'Accept' => 'text/xml' );

    if ( $enta_xml_methods{$method}) {
        $req->header('Content-type' => 'multipart/form-data; type="text/xml"; boundary=' . BOUNDARY);
        $req->header('Content-length' => length $body);
        $req->content($body);
    }

    $res = $ua->request($req);

    die "Request for Enta method $method failed: " . $res->message if $res->is_error;
    my $resp_o = XMLin($res->content);

    if ($resp_o->{Response}->{Type} eq 'Error') { die $resp_o->{Response}->{OperationResponse}->{ErrorDescription}; };
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
    my ( $self, $args ) = @_;
    
    die "You must supply the service-id parameter" unless 
        ( $args->{"ref"} || $args->{"username"} || 
        $args->{"telephone"} || $args->{"service-id"} ||
        $args->{"order-id"} ) ;

    return { "Ref" => $args->{"service-id"} } if $args->{"service-id"};
    return { "Ref" => $args->{"order-id"} } if $args->{"order-id"};
    return { "Ref" => $args->{"ref"} } if $args->{"ref"};
    return { "Username" => $args->{"username"} } if $args->{"username"};
    return { "Telephone" => $args->{"telephone"} } if $args->{"telephone"};
}


=head2 services_available

    $enta->services_available ( { cli => "02072221122" } );

returns a hash the keys of which line speeds available:
    FIXED500, FIXED1000, FIXED2000, RA8, RA24

and the values are the maximum estimated download speed.

=cut

sub services_available {
    my ($self, $args) = @_;
    die "You must supply the cli parameter" unless $args->{"cli"};

    my $details = $self->adslchecker( {cli=>$args->{"cli"}} );

    return undef unless $details->{ErrorCode} eq "0";

    return undef if ( $details->{FixedRate}->{RAG} eq "R" &&
        $details->{RateAdaptive}->{RAG} eq "R" );

    my %avail = ();
    $avail{"adslcheck"} = $details;

    $avail{"RA8"} = $details->{Max}->{Speed} unless $details->{Max}->{RAG} eq "R";

    if ( $details->{FixedRate}->{RAG} =~ /(R|A|G)/ && 
        $details->{RateAdaptive}->{RAG} =~ /^(A|G)$/ ) {
        $avail{"FIXED500"} = "512";
    }

    if ( $details->{FixedRate}->{RAG} =~ /(A|G)/ &&
        $details->{RateAdaptive}->{RAG} eq "G" ) {
        $avail{"FIXED1000"} = "1024";
    }

    if ( $details->{FixedRate}->{RAG} eq "G" && 
        $details->{RateAdaptive}->{RAG} eq "G" ) {
        $avail{"FIXED2000"} = "2048";
    }

    if ( $details->{WBC}->{RAG} && $details->{WBC}->{RAG} ne "R" ) {
        $avail{"RA24"} = $details->{WBC}->{Speed};
    }

    return \%avail;
}

=head2 adslchecker 

    $enta->adslchecker( { cli => "02072221122", mac => "LSDA12345523/DF12D" } );

Returns details from Enta's interface to the BT ADSL checker. See Enta docs
for details of what is returned.

cli parameter is required. mac is optional

=cut

sub adslchecker {
    my ($self, $args) = @_;
    die "You must supply the cli parameter" unless $args->{"cli"};

    my $response = $self->make_request("ADSLChecker", 
        { "PhoneNo" => $args->{cli}, "MACcode" => $args->{mac},
          "Version" => 4 } );

    my %results = ();
    foreach (keys %{$response->{Response}->{OperationResponse}}) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq "HASH" ) {
            my $a = $_;
            foreach (keys %{$response->{Response}->{OperationResponse}->{$a}}) {
                $results{$a}{$_} = $response->{Response}->{OperationResponse}->{$a}->{$_};
            }
        }
        else {
            $results{$_} = $response->{Response}->{OperationResponse}->{$_};
        }
    }
    return \%results;
}

=head2 username_available

    $enta->username_available( username => 'abcdef' );

Returns true if the specified username is available to be used for a 
customer ADSL login at Enta.

=cut

sub username_available {
    my ($self, $args) = @_;
    die "You must provide the username parameter" unless $args->{"username"};

    my $response = $self->make_request("CheckUsernameAvailable", 
        { "username" => $args->{"username"} } );

    return undef if $response->{Response}->{OperationResponse}->{Available} eq "false";
    return 1;
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

    my $line = $self->adslchecker( { 
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
        unless $args->{"interleaving"};

    die "interleaving can only be 'Yes', 'No' or 'Auto'" unless
        $args->{"interleaving"} =~ /(Yes|No|Auto)/;

    my $data = $self->serviceid($args);
    $data->{"LineFeatures"}{"Interleaving"} = $args->{"interleaving"};

    return $self->modifylinefeatures( $data );
}

=head2 stabilityoption 

    $enta->stabilityoption( "service-id" => "ADSL123456", "option" => "Standard" );

Sets the Stability Option feature on a service

=cut

sub stabilityoption {
    my ($self, $args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args->{"option"};

    die "option can only be 'Standard', 'Stable', or 'Super Stable'" unless
        $args->{"option"} =~ /(Standard|Stable|Super Stable)/;

    my $data = $self->serviceid($args);
    $data->{"LineFeatures"}{"StabilityOption"} = $args->{"option"};

    return $self->modifylinefeatures( $data );
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
        unless $args->{"option"};

    die "option can only be 'Yes' or 'No'" unless
        $args->{option} =~ /(Yes|No)/;

    my $data = $self->serviceid($args);

    $data->{"LineFeatures"}->{"ElevatedBestEfforts"} = $args->{"option"};
    $data->{"LineFeatures"}->{"ElevatedBestEffortsFee"} = $args->{"fee"}
        if $args->{"fee"};

    return $self->modifylinefeatures( $data );
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
        unless $args->{"option"};

    die "option can only be 'On' or 'Off'" unless
        $args->{option} =~ /(On|Off)/;

    my $data = $self->serviceid($args);
    my $ec = 4 if $args->{option} eq 'On';
    $ec = 5 if $args->{option} eq 'Off';

    $data->{"LineFeatures"}->{"MaintenanceCategory"} = $ec;
    $data->{"LineFeatures"}->{"MaintenanceCategoryFee"} = $args->{"fee"}
        if $args->{"fee"};

    return $self->modifylinefeatures( $data );
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
            ( $args->{"Ref"} || $args->{"Username"} || 
            $args->{"Telephone"} );

    my $response = $self->make_request("ModifyLineFeatures", $args);

    my %return = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}} ) {
        $return{$_} = $response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}->{$_}->{NewValue};
    }
    return \%return;
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


=head2 cease

    $enta->cease( "service-id" => "ADSL12345", "crd" => "1970-01-01" );

Places a cease order to terminate the ADSL service completely. 

=cut

sub cease {
    my ($self, $args) = @_;
    die "You must provide the crd parameter" unless $args->{"crd"};
    

    my $data = $self->serviceid($args);
    $data->{"CeaseDate"} = $args->{"crd"};
    
    my $response = $self->make_request("CeaseADSLOrder", $data); 

    die "Cease order not accepted by Enta" 
        unless $response->{Response}->{Type} eq 'Accept';

    return { "order-id" => $response->{Response}->{OperationResponse}->{OurRef} };
}

=head2 requestmac

    $enta->requestmac( "service-id" => 'ADSL12345');

Obtains a MAC for the given service. 

Returns a hash comprising: mac, expiry-date if the MAC is available or
submits a request for the MAC which can be obtained later.

=cut

sub requestmac {
    my ($self, $args) = @_;

    my $adsl = $self->adslaccount($args);
    if ( $adsl->{"ADSLAccount"}->{"MAC"} ) {
        my $expires = $adsl->{"ADSLAccount"}->{"MACExpires"};
        $expires =~ s/\+\d+//;
        return { "mac" => $adsl->{"ADSLAccount"}->{"MAC"},
                 "expiry-date" => $expires };
    }

    my $data = $self->serviceid($args);
    
    my $response = $self->make_request("RequestMAC", $data );

    return { "Requested" => 1 };
}

=head2 auth_log

    $enta->auth_log( "service-id" => 'ADSL12345' );

Gets the most recent authentication attempt log

=cut

sub auth_log {
    my ($self, $args) = @_;

    my $data = $self->serviceid($args);
    
    my $response = $self->make_request("LastRadiusLog", $data );

    my %log = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}} ) {
        $log{$_} = $response->{Response}->{OperationResponse}->{$_};
    }
    return \%log;
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
    
    my $data = $self->serviceid($args);
    
    my $response = $self->make_request("AdslAccount", $data );

    my %adsl = ();
    foreach (keys %{$response->{Response}->{OperationResponse}} ) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq 'HASH' ) {
            my $b = $_;
            foreach ( keys %{$response->{Response}->{OperationResponse}->{$b}} ) {
                $adsl{$b}{$_} = $response->{Response}->{OperationResponse}->{$b}->{$_};
            }
        } else {
            $adsl{$_} = $response->{Response}->{OperationResponse}->{$_};
        }
    }
    return \%adsl;
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
        ongoing-payment payment-method totl max-interleaving 
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
    $entatype{"CreateADSLOrder"} = "ADSLMigrationOrder" if $args->{mac};
    my $d = Time::Piece->strptime($args->{"crd"}, "%F");
    $args->{"crd"} = $d->dmy("/");

    my $data = $self->convert_input("CreateADSLOrder", $args);

    my $response = $self->make_request("CreateADSLOrder", $data);

    return { "order-id" => $response->{Response}->{OperationResponse}->{OurRef},
             "service-id" => $response->{Response}->{OperationResponse}->{OurRef},
             "payment-code" => $response->{Response}->{OperationResponse}->{TelephonePaymentCode} };
}

=head2 usage_summary 

    $enta->usage_summary( "service-id" => "ADSL12345", "year" => '2009', "month" => '01' );

=cut 

sub usage_summary {
    my ($self, $args) = @_;
    for (qw/service-id year month/) {
    die "You must provide the $_ parameter" unless $args->{$_}
    }

    my $data = $self->serviceid($args);

    # Need to set $data->{StartDateTime} and $data->{StartDateTime} from
    # the given month and year
    
    my $response = $self->make_request("", $data );
}

=head2 usagehistory 

    $enta->usagehistory( "service-id" =>'ADSL12345' );

Gets a summary of usage for the given service. Optionally a start and end
date for the query may be specified either as a unix timestamp, in which
case the parameters are StartTimestamp and EndTimestamp, or in 
"dd/mm/yyyy hh:mm:ss" format, in which case the parameters are 
StartDateTime and EndDateTime

=cut

sub usagehistory {
    my ($self, $args) = @_;
    die "You must provide the service-id parameter" 
        unless $args->{"service-id"};

    my $data = $self->serviceid($args);
    
    my $response = $self->make_request("", $data );
    
}





1;

