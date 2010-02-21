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
use XML::Simple;
use Time::Piece;
use Time::Seconds;
use Date::Holidays::EnglandWales;

# These are methods for which we have to pass Enta a block of XML as a file
# via POST rather than simply using GET with the parameters and the fields 
# in the XML are case sensitive while they are not when using GET

my %enta_xml_methods = ( "ProductChange" => 1, 
    "ModifyLineFeatures" => 1, "UpdateADSLContact" => 1,
    "CreateADSLOrder" => 1, CeaseADSLOrder => 1 );

my %entatype = ( "CreateADSLOrder" => "ADSLOrder",
    "ModifyLineFeatures" => "ModifyLineFeatures",
    "UpdateADSLContact" => "UpdateADSLContact",
    "CeaseADSLOrder" => "CeaseADSLOrder",
    "ProductChange" => "ProductChange" );

my %formats = (
    ADSLChecker => { "PhoneNo" => "phone", "Version" => "4", "PostCode" => "text",
        "MACcode" => "text" },
    AdslAccount => { "Username" => "username", "Ref" => "ref", "Telephone" => "telephone" },
    ProductChange => { 
        "ProductChange" => {
            "Username" => "username", "Ref" => "ref", "Telephone" => "telephone",
            "NewProduct" => {
                "Family" => "family", "Cap" => "cap", "Speed" => "speed",
            },
            "Schedule" => "schedule",
        },
    },
    ListConnections => { "liveorceased" => "text", "fields" => "text" },
    CheckUsernameAvailable => { "Username" => "username" },
    GetBTFault => { "day" => "text", "start" => "text", "end" => "text" },
    GetAdslInstall => { "Username" => "text", "Ref" => "text" },
    GetBTFeed => { "Days" => "counting" },
    GetNotes => => { "Username" => "text", "Ref" => "text" },
    LastRadiusLog => { "Username" => "text", "Ref" => "text" },
    ConnectionHistory => { "Username" => "text", "Ref" => "text", "Telephone" => "phone", 
        "days" => "counting" },
    GetInterleaving => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    GetOpenADSLFaults => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    RequestMAC => { "Username" => "text", "Ref" => "text", "Telephone" => "phone" },
    UsageHistory => { "Username" => "username", "Ref" => "ref", "Telephone" => "telephone",
        "StartTimeStamp" => "starttimestamp", "EndTimeStamp" => "endtimestamp", 
        "StartDateTime" => "startdatetime", "EndDateTime" => "enddatetime" },
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
    my ($self, $method, $args) = @_;

    my $live = "Test";
    $live = "Live" unless $self->testing;

    my $stupidEnta = 1 if $enta_xml_methods{$method};

    my $xml = qq|<?xml version="1.0" encoding="UTF-8"?>\n<ResponseBlock Type="$live">\n|;
    if ( $stupidEnta ) {
        $xml .= qq|<Response Type="| . $entatype{$method} . qq|">\n<OperationResponse Type="| . $entatype{$method} . qq|">\n|;
    } else {
        $xml .= qq|<OperationResponse Type="| . $entatype{$method} . qq|">\n|;
    }

    my $recurse;
    $recurse = sub {
        my ($format, $data) = @_;
        while (my ($key, $contents) = each %$format) {
            if (ref $contents eq "HASH") {
                if ($key) {
                    if ( $key eq 'ProductChange' ) {
                        my $id = "Ref" if $args->{Ref};
                        $id = "Telephone" if $args->{Telephone};
                        $id = "Username" if $args->{Username};
                        $xml .= qq|<$key $id="|.$args->{$id}.qq|">\n|;
                    }
                    else {
                        $xml .= "\t<$key>\n";
                    }
                }
                $recurse->($contents, $data->{$key});
                if ($key) {
                    $xml .= "</$key>\n";
                }
            } else {
                $xml .= qq{\t\t<$key>}.encode_entities_numeric($args->{$key})."</$key>\n" if $args->{$key};
            }
        }
    };
    $recurse->($formats{$method}, $args); 

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
    $url = ENDPOINT . "xml-beta/$method" . '.php' if $method eq "UsageHistory";
    $url = ENDPOINT . "xml/AdslProductChange" . '.php' if $method eq "ProductChange";
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

    if ( $self->debug ) {
        use Data::Dumper; warn Dumper $req;
        }

    $res = $ua->request($req);
    
    if ( $self->debug ) {
        warn $res->content;
        }

    die "Request for Enta method $method failed: " . $res->message if $res->is_error;
    my $resp_o = XMLin($res->content, SuppressEmpty => 1);

    if ($resp_o->{Response}->{Type} eq 'Error') { die $resp_o->{Response}->{OperationResponse}->{ErrorDescription}; };
    return $resp_o;
}

sub convert_input {
    my ($self, $method, $args) = @_;
    die unless $method && ref $args eq 'HASH';

    my $data = {};

    $args->{ref} = delete $args->{"service-id"} if $args->{"service-id"};

    my $recurse = undef;
    $recurse = sub {
        my ($format, $arg) = @_;
        while (my ($key, $contents) = each %$format) {
            if (ref $contents eq "HASH") {
                $recurse->($contents, $arg->{$key});
            }
            else {
                $data->{$key} = $args->{$contents} if $args->{$contents};
            }
        }
    };

    $recurse->($formats{$method}, $args);

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

    $enta->services_available ( cli => "02072221122" );

Returns an array of hashes which details services available on the given 


returns a hash the keys of which line speeds available:
    FIXED500, FIXED1000, FIXED2000, RA8, RA24

and the values are the maximum estimated download speed.

=cut

sub services_available {
    my ($self, %args) = @_;

    my %details = $self->adslchecker( %args );

    die "It is not possible to obtain information on your phone line" 
        unless $details{ErrorCode} eq "0";

    if ( $details{FixedRate}->{RAG} eq "R" && $details{RateAdaptive}->{RAG} eq "R" ) {
        die "It is not possible to provide any ADSL service on your line";
    }

    if ( $details{MAC} && ( $details{MAC}->{Valid} ne "Y" ) ) {
        die $details{MAC}->{"ReasonCode"};
    }

    my $t = Time::Piece->new();
    $t += ONE_WEEK;

    while ( is_uk_holiday($t->ymd) || ($t->wday == 1 || $t->wday == 7) ) {
        $t += ONE_DAY;
    }

    my @services = ();

    if ( $details{FixedRate}->{RAG} =~ /(R|A|G)/ && 
        $details{RateAdaptive}->{RAG} =~ /^(A|G)$/ ) {
        push @services, {
            "first_date" => $t->ymd,
            "product_id" => "FIXED500",
            "product_name" => "512 Kb/s Fixed Speed",
            "max_speed" => "512",
        };
    }

    if ( $details{FixedRate}->{RAG} =~ /(A|G)/ &&
        $details{RateAdaptive}->{RAG} eq "G" ) {
        push @services, {
            "first_date" => $t->ymd,
            "product_id" => "FIXED1000",
            "product_name" => "1 Mb/s Fixed Speed",
            "max_speed" => "1024",
        };
    }

    if ( $details{FixedRate}->{RAG} eq "G" && 
        $details{RateAdaptive}->{RAG} eq "G" ) {
        push @services, {
            "first_date" => $t->ymd,
            "product_id" => "FIXED2000",
            "product_name" => "2 Mb/s Fixed Speed",
            "max_speed" => "2048",
        };
    }

    if ( $details{Max}->{RAG} ne "R" ) {
        push @services, {
            "first_date" => $t->ymd,
            "product_id" => "RA8",
            "product_name" => "ADSL MAX Up to 8Mb/s",
            "max_speed" => $details{Max}->{Speed},
        };
    }

    if ( $details{WBC}->{RAG} && $details{WBC}->{RAG} ne "R" ) {
        push @services, {
            "first_date" => $t->ymd,
            "product_id" => "RA24",
            "product_name" => "ADSL2+ Up to 24Mb/s",
            "max_speed" => $details{WBC}->{Speed}
        };
    }
    return @services;
}

=head2 regrade_options

    $enta->regrade_options( "service-id" => "ADSL12345" );

Returns an array detailing the available regrade options on the service.

Data returned is the same as from services_available

=cut

sub regrade_options {
    my ($self, %args) = @_;

    my %adsl = $self->adslaccount(%args);
    my $cli = $adsl{ADSLAccount}->{Telephone};

    return $self->services_available( "cli" => $cli );
}

=head2 adslchecker 

    $enta->adslchecker( cli => "02072221122", mac => "LSDA12345523/DF12D" );

Returns details from Enta's interface to the BT ADSL checker. See Enta docs
for details of what is returned.

cli parameter is required. mac is optional

=cut

sub adslchecker {
    my ($self, %args) = @_;

    my $data = {
        "PhoneNo" => $args{cli},
        "PostCode" => $args{postcode},
        "MACcode" => $args{mac},
        "Version" => 4
        } ;

    my $response = $self->make_request("ADSLChecker", $data);

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
    return %results;
}

=head2 username_available

    $enta->username_available( username => 'abcdef' );

Returns true if the specified username is available to be used for a 
customer ADSL login at Enta.

=cut

sub username_available {
    my ($self, $username) = @_;
    die "You must provide the username parameter" unless $username;

    my $response = $self->make_request("CheckUsernameAvailable", 
        { "username" => $username } );

    return undef if $response->{Response}->{OperationResponse}->{Available} eq "false";
    return 1;
}

=head2 verify_mac

    $enta->verify_mac( cli => "02072221111", mac => "ABCD0123456/ZY21X" );

Given a cli and MAC returns 1 if the MAC is valid.

=cut

sub verify_mac {
    my ($self, %args) = @_;
    for (qw/cli mac/) {
        die "You must provide the $_ parameter" unless $args{$_};
    }

    my $line = $self->adslchecker(  
        "cli" => $args{cli}, 
        "mac" => $args{mac} 
        );
    
    return undef unless $line->{MAC}->{Valid};
    return 1;
}

=head2 interleaving

    $enta->interleaving( "service-id" => "ADSL123456", "interleaving" => "No")

Changes the interleaving setting on the given service

=cut

sub interleaving {
    my ($self, %args) = @_;
    die "You must provide the Interleaving parameter plus service identifier"
        unless $args{"interleaving"};

    die "interleaving can only be 'Yes', 'No' or 'Auto'" unless
        $args{"interleaving"} =~ /(Yes|No|Auto)/;

    my $data = $self->serviceid(\%args);
    $data->{"LineFeatures"}->{"Interleaving"} = $args{"interleaving"};

    return $self->modifylinefeatures( %$data );
}

=head2 stabilityoption 

    $enta->stabilityoption( "service-id" => "ADSL123456", "option" => "Standard" );

Sets the Stability Option feature on a service

=cut

sub stabilityoption {
    my ($self, %args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args{"option"};

    die "option can only be 'Standard', 'Stable', or 'Super Stable'" unless
        $args{"option"} =~ /(Standard|Stable|Super Stable)/;

    my $data = $self->serviceid(\%args);
    $data->{"LineFeatures"}->{"StabilityOption"} = $args{"option"};

    return $self->modifylinefeatures( %$data );
}

=head2 elevatedbestefforts

    $enta->elevatedbestefforts( "service-id" => "ADSL123456", "option" => "Yes",
        "fee" => "5.00" );

Enables or disables Elevated Best Efforts on the given service. If the
optional "fee" parameter is passed the monthly fee for this option is 
set accordingly, otherwise it is set to the default charged by Enta.

=cut

sub elevatedbestefforts {
    my ($self, %args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args{"option"};

    die "option can only be 'Yes' or 'No'" unless
        $args{option} =~ /(Yes|No)/;

    my $data = $self->serviceid(\%args);

    $data->{"LineFeatures"}->{"ElevatedBestEfforts"} = $args{"option"};
    $data->{"LineFeatures"}->{"ElevatedBestEffortsFee"} = $args{"fee"}
        if $args{"fee"};

    return $self->modifylinefeatures( %$data );
}

=head2 enhancedcare
    
    $enta->enhancedcare( "service-id" => "ADSL123456", "option" => "On",
        "fee" => "15.00" );

Enables or disabled Enhanced Care on a given service. If the optional
"fee" parameter is passed the monthly fee for this option is set 
accordingly, otherwise it is set to the default charged by Enta.

=cut

sub enhancedcare {
    my ($self, %args) = @_;
    die "You must provide the option parameter plus service identifier"
        unless $args{"option"};

    die "option can only be 'On' or 'Off'" unless
        $args{option} =~ /(On|Off)/;

    my $data = $self->serviceid(\%args);
    my $ec = 4 if $args{option} eq 'On';
    $ec = 5 if $args{option} eq 'Off';

    $data->{"LineFeatures"}->{"MaintenanceCategory"} = $ec;
    $data->{"LineFeatures"}->{"MaintenanceCategoryFee"} = $args{"fee"}
        if $args{"fee"};

    return $self->modifylinefeatures( %$data );
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
    my ($self, %args) = @_;
    die "You must provide the LineFeatures parameter plus service identifier"
        unless $args{LineFeatures};

    my $data = $self->serviceid(\%args);
    $data->{"LineFeatures"} = $args{"LineFeatures"};

    my $response = $self->make_request("ModifyLineFeatures", $data);

    my %return = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}} ) {
        $return{$_} = $response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}->{$_}->{NewValue};
    }
    return \%return;
}

=head2 order_updates_since

    $enta->order_updates_since( "date" => "2009-12-01" );

Returns all the BT order updates since the given date

=cut

sub order_updates_since { 
    my ($self, %args) = @_;
    die "You must provide the date parameter" unless $args{"date"};

    my $from = Time::Piece->strptime($args{"date"}, "%F");
    my $now = localtime;

    my $d = $now - $from;
    my $days = $d->days;
    $days =~ s/\.\d+//;

    my @records = &getbtfeed( $self, $days );

    my @updates = ();
    my %ref = ();
    while (my $r = pop @records) {
        my %a = ();
        my $ref = undef;

        if ( defined $ref{$r->{"Telephone"}} ) { 
            $ref = $ref{$r->{"Telephone"}}; 
        }
        else {
            $ref = $self->_get_ref_from_telephone($r->{"Telephone"});
            $ref{$r->{"Telephone"}} = $ref;
        }

        my ($date, $bst) = split /\+/, $r->{"TimeStamp"};
        chomp $date;
        my $t = Time::Piece->strptime($date, "%a, %d %b %Y %H:%M:%S");

        $a{"date"} = $t->ymd . " " . $t->hms;
        $a{"order-id"} = $ref;
        $a{"name"} = $r->{"OrderType"} . " " . $r->{"CustomerRef"};
        $a{"value"} = $r->{"SubStatus"};
        $a{"value"} .= " " . $r->{"CommitDate"} if $r->{"CommitDate"};

        push @updates, \%a;
    }
    return @updates;
}

=head2 getbtfeed

    $enta->getbtfeed( "days" => 5 );

Returns a list of events that have occurred on all orders over the number of days specified.

Parameters:

    days : The number of days up to the current date to get reports for

The return is an date/time sorted array of hashes each of which contains the following fields:
    order-id
    date
    name
    value

=cut

sub getbtfeed {
    my ($self, %args) = @_;
    die "You must provide the days parameter" unless $args{days};

    my $response = $self->make_request("GetBTFeed", { "Days" => $args{days} });

    my @records = ();
    while ( my $r = pop @{$response->{Response}->{OperationResponse}->{Records}->{Record}} ) {
        push @records, $r;
    }
    return @records;
}


=head2 cease

    $enta->cease( "service-id" => "ADSL12345", "crd" => "1970-01-01" );

Places a cease order to terminate the ADSL service completely. 

=cut

sub cease {
    my ($self, %args) = @_;
    die "You must provide the crd parameter" unless $args{"crd"};

    my %adsl = $self->adslaccount(%args);
    my $data = { "Ref" => $adsl{ADSLAccount}->{OurRef} };

    my $d = Time::Piece->strptime($args{"crd"}, "%F");
    $data->{"CeaseDate"} = $d->dmy('/');
    
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
    my ($self, %args) = @_;

    my %adsl = $self->adslaccount(%args);
    if ( $adsl{"ADSLAccount"}->{"MAC"} ) {
        my $expires = $adsl{"ADSLAccount"}->{"MACExpires"};
        $expires =~ s/\+\d+//;
        return { "mac" => $adsl{"ADSLAccount"}->{"MAC"},
                 "expiry-date" => $expires };
    }

    %args = ( "ref" => $adsl{ADSLAccount}->{OurRef} );

    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("RequestMAC", $data );

    return { "Requested" => 1 };
}

=head2 auth_log

    $enta->auth_log( "service-id" => 'ADSL12345' );

Gets the most recent authentication attempt log

=cut

sub auth_log {
    my ($self, %args) = @_;

    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("LastRadiusLog", $data );

    my %log = ();
    my @r = ();

    my $t = Time::Piece->strptime($response->{Response}->{OperationResponse}->{DateTime}, "%d %b %Y %H:%M:%S");

    $log{"auth-date"} = $t->ymd . ' ' . $t->hms;
    $log{"username"} = $response->{Response}->{OperationResponse}->{Username};
    $log{"result"} = "Login OK";
    $log{"ipaddress"} = $response->{Response}->{OperationResponse}->{IPAddress};

    push @r, \%log;
    return @r;
}

=head2 max_reports

    $enta->max_reports( "service-id" => "ADSL12345" );

Returns the ADSL MAX reports for connections which are based upon ADSL MAX

=cut

sub max_reports {
    my ($self, %args) = @_;
    
    my $data = $self->serviceid(\%args);

    my $response = $self->make_request("GetMaxReports", $data);

    my %line = ();
    my @rate = ();
    my @profile = ();

    while ( my $r = shift @{$response->{"Response"}->{"Report"}} ) {
        if ( $r->{"Name"} eq "Line RateChange" ) {
            while (my $rec = shift @{$r->{Record}} ) {
                push @rate, $rec;
            }
        }
        elsif ( $r->{"Name"} eq "Service Profile" ) {
            while (my $rec = shift @{$r->{Record}} ) {
                push @profile, $rec;
            }
        }
    }
    $line{"ratechange"} = \@rate;
    $line{"profile"} = \@profile;

    return %line;
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
    my ($self, %args) = @_;
    
    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("AdslAccount", $data );

    my %adsl = ();
    foreach (keys %{$response->{Response}->{OperationResponse}} ) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq 'HASH' ) {
            my $b = $_;
            foreach ( keys %{$response->{Response}->{OperationResponse}->{$b}} ) {
                $adsl{$b}{$_} = $response->{Response}->{OperationResponse}->{$b}->{$_};
            }
        }
        else {
            $adsl{$_} = $response->{Response}->{OperationResponse}->{$_};
        }
    }
    return %adsl;
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


=head2 product_change

    $enta->product_change( "username" => "myusername", "family" => "Family",
        "cap" => "30", "speed" => "8000" );

Place an order to change the specified service to the given new product.

Note that you can only use username or telephone to identify the service. 
You cannot use ref or service-id

=cut

sub product_change {
    my ($self, %args) = @_;
    die "You must pass either the Username or Telephone parameter" if ( $args{"ref"} || $args{"service-id"});

    $args{schedule} = "FirstAvailableDate";

    my $data = $self->convert_input("ProductChange", \%args);
    my $response = $self->make_request("ProductChange", $data);

    return $response->{Response}->{OperationResponse}->{ProductChange}->{Results};
}

=head2 regrade

    $enta->regrade( "service-id" => "ADSL12345",
                    "prod-id" => "FAM30" );

Places an order to regrade the specified service to the specified prod-id.

Required parameters:

    prod-id : New Enta product ID
    service-id : you must provide one of service-id, ref, username or telephone

=cut

sub regrade {
    my ($self, %args) = @_;

    my %adsl = $self->adslaccount(%args);
    my %data = ( "username" => $adsl{ADSLAccount}->{Username} );

    my $speed = $adsl{ADSLAccount}->{ActualBTProduct};

    if ( ( $speed =~ /Premium/ && $args{"prod-id"} !~ /BUS/ ) ||
         ( $speed !~ /Premium/ && $args{"prod-id"} =~ /BUS/ ) ) {
        die "To switch between a Family and Business product requires a manual request to Enta";
    }

    $speed = "24000" if $speed eq 'WBC End User Access (EUA)';
    $speed = "8000" if $speed =~ /BT IPStream Max/;
    $speed = "2000" if $speed =~ /BT IPStream .* 2000/;
    $speed = "1000" if $speed =~ /BT IPStream .* 1000/;
    $speed = "500" if $speed =~ /BT IPStream .* 500/;

    $data{speed} = $speed;

    if ( $args{"prod-id"} =~ /(\D+)(\d+)/ ) {
        print "$1 : $2\n";
        my $family = "Family";
        $family = "Business" if $1 eq 'BUS';
        $data{family} = $family;
        $data{cap} = $2;

        return $self->product_change(%data);
    }
}

=head2 usage_summary 

    $enta->usage_summary( "service-id" => "ADSL12345", "year" => '2009', "month" => '01' );

Returns a summary of usage in the given month

=cut 

sub usage_summary {
    my ($self, %args) = @_;
    for (qw/ year month /) {
        die "You must provide the $_ parameter" unless $args{$_};
    }

    my $data = $self->serviceid(\%args);

    my $s = $args{year}."-".$args{month}."-1";
    my $start = Time::Piece->strptime($s, "%F");
    $args{"startday"} = $start->ymd;

    my $e = $args{year}."-".$args{month}."-".$start->month_last_day;
    my $end = Time::Piece->strptime($e, "%F");
    $args{"endday"} = $end->ymd;

    my @history = $self->usagehistorydetail(%args);
    my $downstream = 0;
    my $upstream = 0;
    my $peakdownstream = 0;
    my $peakupstream = 0;

    while ( my $h = pop @history ) {
        $downstream += $h->{Total}->{Down};
        $upstream += $h->{Total}->{Up};
        $peakdownstream += $h->{Peak}->{Down};
        $peakupstream += $h->{Peak}->{Up};
    }

    return (
        "year" => $args{"year"},
        "month" => $args{"month"},
        "total-input-octets" => $downstream,
        "total-output-octets" => $upstream,
        "peak-input-octets" => $peakdownstream,
        "peak-output-octets" => $peakupstream
    );
}

sub usage_history {
    my ($self, %args) = @_;

    if ( $args{startdatetime} ) {
        my $s = Time::Piece->strptime($args{startdatetime}, "%Y-%m-%d %H:%M:%S");
        $args{startdatetime} = $s->dmy('/') . ' ' . $s->strftime("%H:%M:%S");
    }
    if ( $args{enddatetime} ) {
        my $s = Time::Piece->strptime($args{enddatetime}, "%Y-%m-%d %H:%M:%S");
        $args{enddatetime} = $s->dmy('/') . ' ' . $s->strftime("%H:%M:%S");
    }

    my $data = $self->convert_input("UsageHistory", \%args);

    $data->{RawDisplay} = 1;

    my $response = $self->make_request("UsageHistory", $data);

    use Data::Dumper;
    print Dumper $response;

}

sub usagehistorydetail {
    my ($self, %args) = @_;

    my $data = $self->serviceid(\%args);

    if ( $args{"day"} ) {
        my $d = Time::Piece->strptime($args{"day"}, "%F");
        $data->{"day"} = $d->dmy('/');
    }
    elsif ( $args{"startday"} && $args{"endday"} ) {
        my $s = Time::Piece->strptime($args{"startday"}, "%F");
        my $e = Time::Piece->strptime($args{"endday"}, "%F");
        $data->{"startday"} = $s->dmy('/');
        $data->{"endday"} = $e->dmy('/');
    }
    else {
        die "You must provide the day parameter or the startday and endday parameters";
    }

    my $response = $self->make_request("UsageHistoryDetail", $data);

    my @usage = ();
    if ( $args{"day"} ) {
        @usage = @{$response->{ResponseType}->{Detail}->{Usage}};
    }
    else {
        @usage = @{$response->{ResponseType}->{Day}};
    }

    return @usage;
}

=head2 session_log

    $enta->session_log( "service-id" => "ADSL12345", "days" => 5 );

Returns details of recent ADSL sessions - optionally specifying the number
of days for how recent.

=cut

sub session_log {goto &connectionhistory; }


=head2 connectionhistory

    $enta->connectionhistory( "service-id" => "ADSL12345", "days" => 5 );

Returns details of recent ADSL sessions - optionally specifying the number
of days for how recent.

=cut

sub connectionhistory {
    my ($self, %args) = @_;
  
    # Enta ConnectionHistory is keyed from Username only so we need to 
    # obtain the username if we don't have it.

    my $data = undef;
    if ( ! $args{"username"} ) {
        my %adsl = $self->adslaccount(%args);
        $data = { "username" => $adsl{ADSLAccount}->{Username} };
    }
    else {
        $data = $self->serviceid(\%args);
    }

    $data->{days} = $args{days} if $args{days};

    my $response = $self->make_request("ConnectionHistory", $data);
    
    my @history = ();

    if ( ref $response->{Response}->{OperationResponse}->{Connection} eq 'ARRAY' ) {
        while ( my $h = pop @{$response->{Response}->{OperationResponse}->{Connection}} ) {
            my %a = ();
            my $start = Time::Piece->strptime($h->{"StartDateTime"}, "%d %b %Y %H:%M:%S");
            my $end = Time::Piece->strptime($h->{"EndDateTime"}, "%d %b %Y %H:%M:%S");
            $a{"start-time"} = $start->ymd." ".$start->hms;
            $a{"stop-time"} = $end->ymd." ".$end->hms;
            $a{"duration"} = $end->epoch - $start->epoch;
            $a{"username"} = $h->{"Username"};

            my ($download, $upload, $measure) = ();

            ($upload, $measure) = split(/\s/, $h->{"Input"});
            
            $a{"upload"} = $upload * 1024*1024*1024 if $measure eq 'GB';
            $a{"upload"} = $upload * 1024*1024 if $measure eq 'MB';
            $a{"upload"} = $upload * 1024 if $measure eq 'KB';

            ($download, $measure) = split(/\s/, $h->{"Output"});

            $a{"download"} = $download * 1024*1024*1024 if $measure eq 'GB';
            $a{"download"} = $download * 1024*1024 if $measure eq 'MB';
            $a{"download"} = $download * 1024 if $measure eq 'KB';

            $a{"termination-reason"} = "Session Ended";

            push @history, \%a;
        }
    }
    else {
        my %a = ();
        my $start = Time::Piece->strptime($response->{Response}->{OperationResponse}->{Connection}->{"StartDateTime"}, "%d %b %Y %H:%M:%S");
        my $end = Time::Piece->strptime($response->{Response}->{OperationResponse}->{Connection}->{"EndDateTime"}, "%d %b %Y %H:%M:%S");
        $a{"start-time"} = $start->ymd." ".$start->hms;
        $a{"stop-time"} = $end->ymd." ".$end->hms;
        $a{"duration"} = $end - $start;
        $a{"username"} = $response->{Response}->{OperationResponse}->{Connection}->{"Username"};

        my ($download, $upload, $measure) = ();

        ($upload, $measure) = split $response->{Response}->{OperationResponse}->{Connection}->{"Input"};
        $a{"upload"} = $upload * 1024*1024*1024 if $measure eq 'GB';
        $a{"upload"} = $upload * 1024*1024 if $measure eq 'MB';
        $a{"upload"} = $upload * 1024 if $measure eq 'KB';

        ($download, $measure) = split $response->{Response}->{OperationResponse}->{Connection}->{"Output"};
        $a{"download"} = $download * 1024*1024*1024 if $measure eq 'GB';
        $a{"download"} = $download * 1024*1024 if $measure eq 'MB';
        $a{"download"} = $download * 1024 if $measure eq 'KB';

        $a{"termination-reason"} = "Session Ended";

        push @history, \%a;
    }
    return @history;
}

=head2 first_crd

    $enta->first_crd( "order-type" => "provide", "product-id" => "FAM30" );

Returns the first date an order may be placed for.

Parameters: 

    order-type
    product-id

=cut

sub first_crd {
    my ($self, %args) = @_;
    
    my $t = Time::Piece->new();
    $t += ONE_WEEK;

    while ( is_uk_holiday($t->ymd) || ($t->wday == 1 || $t->wday == 7) ) {
        $t += ONE_DAY;
    }

    return $t->ymd;
}

sub _get_ref_from_telephone {
    my ($self, $cli) = @_;

    my %adsl = $self->adslaccount( "telephone" => $cli );
    return $adsl{ADSLAccount}->{OurRef};
}

1;
