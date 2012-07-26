package Net::DSLProvider::Entanet;

# This replaces the Net::DSLProvider::Enta module

use strict;
use warnings;
use HTML::Entities qw(encode_entities_numeric);
use base 'Net::DSLProvider';
use constant ENDPOINT => "https://api.enta.net/xml/";
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

my %requesttype = ( RequestAppointmentBook => "post", Poll => "post",
    RequestAppointmentSlot => "post", ADSLChecker => "get", 
    GetBlocked => "get", ModifyLineFeatures => "post", GetNotes => "get",
    GetRateLimited => "get", AdslAccount => "get", GetBTFault => "get",
    ListConnections => "get", CheckUsernameAvailable => "get",
    GetAdslInstall => "get", PendingOrders => "get", GetBTFeed => "get",
    PSTNPendingOrders => "get", LastRadiusLog => "get",
    ConnectionHistory => "get", GetInterleaving => "get",
    GetOpenADSLFaults => "get", RequestMAC => "get", ADSLTopup => "get",
    UsageHistory => "get", GetMaxReports => "get", GetHeavyUsers => "get",
    UpdateADSLPrice => "post", UpdateADSLContact => "post", 
    GetADSLUsage => "get", CreateLLUOrder => "post",
    CreateADSLOrder => "post"
    );

my %formats = (
# Appointments Methods
    RequestAppointmentBook => { Date => "dd/mm/yyyy",
        TelephoneNumber => "phone",
        listOfAttributes => "text"
    },
    RequestAppointmentSlot => {
        Date => "dd/mm/yyyy", TimeSlot => "text",
        TelephoneNumber => "phone", listOfAttributes => "text"
    },
    Poll => { Token => "text" },
# ADSL Checker Method
    ADSLChecker => { "PhoneNo" => "phone", "PostCode" => "text",
        "MACcode" => "text", EUPostCode => "text"
    },
# Get Blocked Connections
    GetBlocked => { "Username" => "username", 
        "Ref" => "ref", "Telephone" => "telephone"
    },
# Modify Line Features
    ModifyLineFeatures => { "ADSLAccount" => {
        "Ref" => "text", "Username" => "text", "Telephone" => "phone",
        "LineFeatures" => {
            "Interleaving" => "text", "StabilityOption" => "text", 
            "ElevatedBestEfforts" => "yesno", "ElevatedBestEffortsFee" => "text", 
            "MaintenanceCategory" => "counting", "MaintenanceCategoryFee" => "text",
            Upstream => "text", UpstreamFee => "text"
            }
        }
    },
# Get Rate Limited Connections
    GetRateLimited => { Username => 1, Ref => 1, Telephone => 1 },
# Reporting Tools
    AdslAccount => { Username => 1, Ref => 1, Telephone => 1 },
    ListConnections => { liveorceased => 1, fields => 1 },
    CheckUsernameAvailable => { username => 1 },
    GetBTFault => { day => 1, start => 1, end => 1 },
    GetAdslInstall => { Username => 1, Ref => 1 },
    GetBTFeed => { Days => 1 },
    GetNotes => => { Username => 1, Ref => 1 },
    PendingOrders => { },
    PSTNPendingOrders => { },
    LastRadiusLog => { Username => 1, Ref => 1 },
    ConnectionHistory => { Username => 1, Ref => 1, Telephone => 1,
        Days => 1 },
    GetInterleaving => { Username => 1, Ref => 1, Telephone => 1 },
    GetOpenADSLFaults => { Username => 1, Ref => 1, Telephone => 1 },
    RequestMAC => { Username => 1, Ref => 1, Telephone => 1 },
    UsageHistory => { Username => 1, Ref => 1, Telephone => 1,
        "StartTimestamp" => "starttimestamp", "EndTimestamp" => "endtimestamp", 
        "StartDateTime" => "startdatetime", "EndDateTime" => "enddatetime" },
    UsageHistoryDetail => { Username => 1, Ref => 1, Telephone => 1,
        "startday" => "dd/mm/yyyy", "endday" => "dd/mm/yyyy", "day" => "dd/mm/yyyy" },
    GetMaxReports => { Username => 1, Ref => 1, Telephone => 1 },
# ADSL TopUp
    ADSLTopup => { Username => 1, Ref => 1, Telephone => 1 },
# Heavy User Tool
    GetHeavyUsers => { Username => 1, Ref => 1, Telephone => 1 },
# Update ADSL Price
    UpdateADSLPrice => { ADSLAccount => {
        Username => 1, Ref => 1, Telephone => 1, 
        PriceDetails => {
            PeriodFee => 1, EnhancedCareFee => 1, 
            ElevatedBestEffortsFee => 1 }
        }
    },
# Update ADSL Contact Details
    UpdateADSLContact => { ADSLAccount => {
        Username => 1, Ref => 1, Telephone => 1, ContactDetails => {
            Email => 1, TelDay => 1, TelEve => 1 }
        }
    },
# Usage Information    
    GetADSLUsage => { FromDate => 1, ToDate => 1, MinUsage => 1, 
        Product => 1, ReturnType => 1
    },
# LLU Create Order
    CreateLLUOrder => {
        ADSLAccount => {
            Product => 1, Title => 1, FirstName => 1, Surname => 1, 
            CompanyName => 1, Building => 1, Street => 1, Town => 1,
            County => 1, Postcode => 1, TelephoneDay => 1, 
            TelephoneEvening => 1, Fax => 1, Email => 1, Telephone => 1, 
            ProvisionDate => 1, MAC => 1, 
            Charges => {
                Initial => 1, Recurring => 1
            },
            RadiusDetails => {
                Username => 1, Password => 1, Realm => BaseDomain => 1,
                IPAddresses => {
                    IPv4 => { NumberRequired => 1 },
                    IPv6 => { Enabled => 1 }
                }
            }
        }
        BillingAccount => {
            ContractTerm => 1, BillingPeriod => 1,
            InitialPaymentMethod => 1, OngoingPaymentMethod => 1, 
            PaymentMethod => 1, PurchaseOrderNumber => 1
        }.
        CustomerRecord => {
            cCustomerID => 1, cTitle => 1, cFirstName => 1, 
            cSurname => 1, cCompanyName => 1, cBuilding => 1, 
            cStreet => 1, cTown => 1, cCounty => 1, cPostcode => 1, 
            cTelephoneDay => 1, cTelephoneEvening => 1, cFax => 1,
            cEmail => 1
        }
    },
# Create ADSL / FTTC Order (not LLU)
    CreateADSLOrder => {
        ADSLAccount => {
            Product => 1, ProductInitialFee => 1, 
            ProductOngoingFee => 1, Title => 1, FirstName => 1,
            Surname => 1, CompanyName => 1, Building => 1, Street => 1,
            Town => 1, County => 1, Postcode => 1, OnsiteHazards => 1, 
            TelephoneDay => 1, TelephoneEvening => 1, Fax => 1, 
            Email => 1, Telephone => 1, ProvisionDate => 1, NAT => 1, 
            InitialNoNATFee => 1, NoNatReason => 1, Username => 1,
            Password => 1, ISPName => 1, CareLevel => 1, 
            InitialCareLevelFee => 1, OngoingCareLevelFee => 1, 
            LineSpeed => 1, OveruseMethod => 1, MaxPAYGAmount => 1,
            MAC => 1, Realm => 1, BaseDomain => 1, StabilityOption => 1,
            Interleave => 1, BestEfforts => 1, BestEffortsInitialFee => 1,
            BestEffortsOngoingFee => 1, InstallFee => 1, Upstream => 1,
            UpstreamInitialFee => 1, UpstreamOngoingFee => 1,
            AssignIPV6 => 1
        },
        BillingAccount => {
            PurchaseOrderNumber => 1, BillingPeriod => 1, 
            ContractTerm => 1, InitialPaymentMethod => 1,
            OngoingPaymentMethod => 1, PaymentMethod => 1
        },
        CustomerRecord => {
            cCustomerID => 1, cTitle => 1, cFirstName => 1,
            cSurname => 1, cCompanyName => 1, cBuilding => 1,
            cStreet => 1, cTown => 1, cCounty => 1, cPostcode => 1,
            cTelephoneDay => 1, cTelephoneEvening => 1, cFax => 1,
            cEmail => 1
        },
        AppointmentDetails => {
            AppointmentReference => 1
        }
    }
);

sub request_xml {
    my ($self, $method, $args) = @_;

    my $live = "Test";
    $live = "Live" unless $self->testing;

    my $xml = qq|<?xml version="1.0" encoding="UTF-8"?>\n
    <ResponseBlock Type="$live">\n
    <Response Type="$method">\n
    <OperationResponse>|;

    # XXX Waiting for confirmation from Enta that they will make API
    # XXX consistent with regard to XML structure!

    if ( $enta_xml_methods{$method} ) {
        if ( $method eq 'CeaseADSLOrder' ) {
            $xml .= qq|<Response Type="ADSLCease">\n<OperationResponse">\n|;
        }
        else { 
            $xml .= qq|<Response Type="| . $entatype{$method} . qq|">\n<OperationResponse Type="| . $entatype{$method} . qq|">\n|;
        }
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

    if ( $enta_xml_methods{$method} ) {
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

    my $version = 'stable';
    my $version = @{[$self->version]} if @{[$self->version]};

    my $url = ENDPOINT . "$version/$method" . '.php';

    if ( $requesttype{$method} eq 'post' ) {
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

    if ( $requesttype{$method} eq 'post' ) {
        $req->header('Content-type' => 'multipart/form-data; type="text/xml"; boundary=' . BOUNDARY);
        $req->header('Content-length' => length $body);
        $req->content($body);
    }

    $self->debug_dump($req) if $self->debug;

    $res = $ua->request($req);
    
    $self->debug_dump($res->content) if $self->debug;

    die "Request for Enta method $method failed: " . $res->message if $res->is_error;

    # Sometimes Enta doesn't return anything at all on success
    return undef unless $res->content;

    my $resp_o = XMLin($res->content, SuppressEmpty => 1);

    if ($resp_o->{Response}->{Type} eq 'Error') { die $resp_o->{Response}->{OperationResponse}->{ErrorDescription}; };

    my $recurse = undef;
    $recurse = sub {
        my $input = shift;
        while ( my ($oldkey, $contents) = each %$input ) {
            my $newkey = $oldkey;
            $newkey =~ s/-/_/g;
            $input->{$newkey} = $recurse->($contents), if ref $contents eq 'HASH';
            if ( ref $contents eq "ARRAY" ) {
                for my $r ( @{$contents} ) {
                    $recurse->($r);
                }
            }
            $input->{$newkey} = $contents;
            delete $input->{$oldkey} if $oldkey =~ /-/;
        }
    };

    $recurse->($resp_o);

    $self->debug_dump($resp_o) if $self->debug;

    if ( $resp_o->{Response}->{OperationResponse} ) {
        return $resp_o->{Response}->{OperationResponse};
    }
    else {
        return $resp_o->{Response};
    }
}

sub convert_input {
    my ($self, $method, $args) = @_;
    die "convert_input called without method or args hashref" unless $method && ref $args eq 'HASH';

    my $data = {};

    $args->{'ref'} = delete $args->{"service-id"} if $args->{"service-id"};
    $args->{telephone} = $args->{cli} if ((!$args->{telephone}) && $args->{cli});

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
    return { "Telephone" => $args->{"cli"} } if $args->{"cli"};
}


=head2 services_available

    $enta->services_available ( cli => "02072221122" );

Returns a hash showing line qualification data    

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

    my %rv = ();
    my $top = undef;

    if ( $details{FixedRate}->{RAG} =~ /(R|A|G)/ && 
        $details{RateAdaptive}->{RAG} =~ /^(A|G)$/ ) {
        $rv{qualification}->{classic} = 512000;
    }

    if ( $details{FixedRate}->{RAG} =~ /(A|G)/ &&
        $details{RateAdaptive}->{RAG} eq "G" ) {
        $rv{qualification}->{classic} = 1024000;
    }

    if ( $details{FixedRate}->{RAG} eq "G" && 
        $details{RateAdaptive}->{RAG} eq "G" ) {
        $rv{qualification}->{classic} = 2048000;
    }
    $top = $rv{qualification}->{classic};

    if ( $details{Max}->{RAG} ne "R" ) {
        $rv{qualification}->{max} = $details{Max}->{Speed} * 1024;
        $top = $rv{qualification}->{max};
    }

    if ( $details{WBC}->{RAG} && $details{WBC}->{RAG} ne "R" ) {
        $rv{qualification}->{'2plus'} = $details{WBC}->{Speed} * 1024;
        $top = $rv{qualification}->{'2plus'};
    }

    if ( $details{FullMsg} =~ /WBC FTTC Broadband where consumers have received downstream line speed of (.*)Mbps and upstream line speed of (.*)Mbps/g ) {
        $rv{qualification}->{fttc} = {
            down => $1 * 1024*1024,
            up => $2 * 1024*1024
        };
    }
    if ( $details{FullMsg} =~ /Your cabinet is planned to have WBC FTTC by (.*)(\d{4})\./s ) {
        my $planned = $1;
        my $year = $2;
        my $nth = '(st|nd|rd|th)';
        $planned =~ s/(\d+)$nth /$1 /;
        $planned = $planned . $year;
        my $date = Time::Piece->strptime($planned, "%d %b %Y");
        $rv{qualification}->{fttc}->{date} = $date->ymd;
    }

    $rv{qualification}->{'first_date'} = $t->ymd;
    foreach (qw/FAM1 FAM3 FAM30 FAM60 FAM90 FAM120 BUS15/) {
        $rv{$_} = {
            first_date => $t->ymd,
            product_name => $_,
            max_speed => $top
        };
    }   
    foreach (qw/BUS45 BUS90 BUS135 BUS180/) {
        $rv{$_} = {
            first_date => $t->ymd,
            product_name => $_,
            max_speed => defined $rv{qualification}->{fttc}->{down} ? $rv{qualification}->{fttc}->{down} : $top
        };
    }

    return %rv;
}

=head2 get_appointments
    $enta->get_appointments( cli => "02070010001",
        date => "2012-01-01",
        attributes => { ExtensionKit => 1 }
    );

Returns an array listing available appointment slots or, if it is not 
possible to obtain appointments, returns a token to poll for the 
list at a later point.

Required parameters:

    cli         Telephone Number
    date        Earliest date for appointments

Optional parameters:

    attributes  Hash ref of required extensions (see Enta docs)

=cut

sub get_appointments {
    my ($self, %args) = @_;
    return unless $args{cli} && $args{date};

    my $data = {
        Telephone => $args{cli},
        Date => $args{date}
    }
    foreach (keys %{$args{attributes}}) {
        $data->{listOfAttributes}->{$_} = $args{attributes}->{$_};
    }

    my $response = $self->make_request("RequestAppointmentBook", $data);


}

=head2 regrade_options

    $enta->regrade_options( "service-id" => "ADSL12345" );

Returns an array detailing the available regrade options on the service.

Data returned is the same as from services_available

=cut

sub regrade_options {
    my ($self, %args) = @_;

    my %adsl = $self->adslaccount(%args);
    my $cli = $adsl{adslaccount}->{telephone};

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
    $self->_check_params(\%args, ("cli|postcode"));

    my $data = {
        "PhoneNo" => $args{cli},
        "PostCode" => $args{postcode},
        "MACcode" => $args{mac},
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
    $self->_check_params(\%args, qw/cli mac/);

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

=head2 interleaving_status

    $enta->interleaving_status( "service-id" => "ADSL12345" );

Returns the current interleaving status if available

=cut

sub interleaving_status {
    my ( $self, %args ) = @_;
    $self->_check_params(\%args, qw/service-id|username|telephone|ref/);

    my $data = $self->serviceid(\%args);
    my $response = $self->make_request("GetInterleaving", $data);

    return $response->{Response}->{OperationResponse}->{Interleave};

}

=head2 interleaving

    $enta->interleaving( "service-id" => "ADSL123456", "interleaving" => "No")

Changes the interleaving setting on the given service

=cut

sub interleaving {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ("service-id|ref|telephone|username", "interleaving"));

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
    $self->_check_params(\%args, ("service-id|ref|telephone|username", "option"));

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
    $self->_check_params(\%args, ("service-id|ref|telephone|username", "option"));

    die "option can only be 'Yes' or 'No'" unless
        $args{option} =~ /(Yes|No)/;

    my $data = $self->serviceid(\%args);

    $data->{"LineFeatures"}->{"ElevatedBestEfforts"} = $args{"option"};
    $data->{"LineFeatures"}->{"ElevatedBestEffortsFee"} = $args{"fee"}
        if $args{"fee"};

    return $self->modifylinefeatures( %$data );
}

=head2 change_carelevel

    $enta->carei_level( "service-id" -> "ADSL12345", "care-level" => "enhanced" );

Changes the care-level associated with a given service. 

care-level can be set to either standard or enhanced.

Returns true is successful.

=cut

sub care_level {
    my ($self, %args) = @_;
    $self->_check_params( \%args );

    my %data = %args;

    $data{option} = 'On' if $args{"care-level"} eq 'enhanced';
    $data{option} = 'Off' if $args{"care-level"} eq 'standard';

    return $self->enhanced_care(%data);
}

=head2 enhanced_care
    
    $enta-enhanced_care( "service-id" => "ADSL123456", "option" => "On",
        "fee" => "15.00" );

Enables or disabled Enhanced Care on a given service. If the optional
"fee" parameter is passed the monthly fee for this option is set 
accordingly, otherwise it is set to the default charged by Enta.

=cut

sub enhanced_care {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ("service-id|ref|telephone|username", "option"));

    die "option can only be 'On' or 'Off'" unless $args{option} =~ /(On|Off)/;

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
    $self->_check_params(\%args, ("service-id|ref|telephone|username", "LineFeatures"));

    my $data = $self->serviceid(\%args);
    $data->{"LineFeatures"} = $args{"LineFeatures"};

    my $response = $self->make_request("ModifyLineFeatures", $data);

    my %return = ();
    foreach ( keys %{$response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}} ) {
        $return{lc $_} = $response->{Response}->{OperationResponse}->{ADSLAccount}->{LineFeatures}->{$_}->{NewValue};
    }
    return \%return;
}

=head2 order_updates_since

    $enta->order_updates_since( "date" => "2009-12-01" );

Returns all the BT order updates since the given date

=cut

sub order_updates_since { 
    my ($self, %args) = @_;
    $self->_check_params(\%args, (qw/date/));

    my $from = Time::Piece->strptime($args{"date"}, "%F");
    my $now = localtime;

    my $d = $now - $from;
    my $days = $d->days;
    $days =~ s/\.\d+//;

    my $date_format = "%Y-%m-%d %H:%M:%S";
    $date_format = $args{dateformat} if $args{dateformat};

    my @records = $self->getbtfeed( "days" => $days );

    my @updates = ();
    my %ref = ();
    while (my $r = pop @records) {
        my %a = ();
        my $ref = undef;

        if ( defined $ref{$r->{"telephone"}} ) { 
            $ref = $ref{$r->{"telephone"}}; 
        }
        else {
            eval { $ref = $self->_get_ref_from_telephone($r->{"telephone"}) };
            $ref = $r->{"customerref"} if ( ! $ref && $r->{"customerref"} =~ /^ADSL\d+$/);
            $ref = $r->{"telephone"} if ! $ref;
        }

        $r->{"timestamp"} =~ /(.*) \+0\d00/;
        my $t = Time::Piece->strptime($1, "%a, %d %b %Y %H:%M:%S");

        $a{"date"} = $t->strftime($date_format);
        $a{"order_id"} = $ref;
        $a{"name"} = $r->{"ordertype"} . " " . $r->{"customerref"};
        $a{"value"} = $r->{"substatus"};
        $a{"value"} .= " " . $r->{"commitdate"} if $r->{"commitdate"};

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
    $self->_check_params(\%args, (qw/days/));

    my $response = $self->make_request("GetBTFeed", { "Days" => $args{days} });

    my @records = ();
    while ( my $r = pop @{$response->{Response}->{OperationResponse}->{Records}->{Record}} ) {
        my %a = ();
        foreach (keys %$r) {
            $a{lc $_} = $r->{$_};
        }
        push @records, \%a;
    }
    return @records;
}

=head2 update_contact

    $enta->update_contact( "service-id" => "ADSL12345", 
                            email => 'me@example.com',
                            telday => '02070020011',
                            televe => '02080020011' );

Updates the given contact details. Returns true if updated.

You can use this to change the email address, daytime telephone number
and evening telephone number of the contact for the given service.

=cut

sub update_contact {
    my ( $self, %args) = @_;
    $self->_check_params(\%args);

    my $data = $self->serviceid(\%args);
    for (qw/Email TelDay TelEve/) {
        $data->{$_} = $args{lc $_} if $args{lc $_};
    }

    my $response = $self->make_request("UpdateADSLContact", $data);
    return 1;
}

=head2 cease

    $enta->cease( "service-id" => "ADSL12345", "crd" => "1970-01-01" );

Places a cease order to terminate the ADSL service completely. 

=cut

sub cease {
    my ($self, %args) = @_;
    $self->_check_params(\%args);

    my $data = undef;
    if ( $args{'service-id'} || $args{'ref'} ) {
        $data = $self->convert_input("CeaseADSLOrder" ,\%args);
    }
    else {
        my %adsl = $self->adslaccount(%args);
        $data = { "username" => $adsl{adslaccount}->{username} };
    }

    my $d = Time::Piece->strptime($args{"crd"}, "%F");
    $data->{"ceaseDate"} = $d->dmy('/');
    
    my $response = $self->make_request("CeaseADSLOrder", $data);

    die "Cease order not accepted by Enta" unless $response->{Response}->{Type} eq 'Accept';

    return $response->{Response}->{OperationResponse}->{OurRef};
}

=head2 requestmac

    $enta->requestmac( "service-id" => 'ADSL12345');

Obtains a MAC for the given service. 

Returns a hash comprising: mac, expiry-date if the MAC is available or
submits a request for the MAC which can be obtained later.

=cut

sub request_mac {
    my ($self, %args) = @_;
    $self->_check_params(\%args);

    my %adsl = $self->adslaccount(%args);
    if ( $adsl{"adslaccount"}->{"mac"} ) {
        my $expires = $adsl{"adslaccount"}->{"macexpires"};
        $expires =~ s/\+\d+//;
        return ( "mac" => $adsl{"adslaccount"}->{"mac"},
                 "expiry_date" => $expires );
    }

    %args = ( "ref" => $adsl{adslaccount}->{ourref} );

    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("RequestMAC", $data );

    return ( "mac_requested" => 1 );
}

=head2 auth_log

    $enta->auth_log( "service-id" => 'ADSL12345' );

Gets the most recent authentication attempt log.

=cut

sub auth_log {
    my ($self, %args) = @_;
    $self->_check_params(\%args);

    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("LastRadiusLog", $data );

    my %log = ();
    my @r = ();
    
    my $date_format = "%Y-%m-%d %H:%M:%S";
    $date_format = $args{dateformat} if $args{dateformat};

    my $t = Time::Piece->strptime($response->{Response}->{OperationResponse}->{DateTime}, "%d %b %Y %H:%M:%S");

    $log{"auth_date"} = $t->strftime($date_format);
    $log{"username"} = $response->{Response}->{OperationResponse}->{Username};
    $log{"result"} = "Login OK";
    $log{"ip_address"} = $response->{Response}->{OperationResponse}->{IPAddress};

    push @r, \%log;
    return @r;
}

=head2 max_reports

    $enta->max_reports( "service-id" => "ADSL12345" );

Returns the ADSL MAX reports for connections which are based upon ADSL MAX

=cut

sub max_reports {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ("ref|telephone|username|service-id"));
    
    my $data = $self->serviceid(\%args);

    my $response = $self->make_request("GetMaxReports", $data);

    my %line = ();
    my @rate = ();
    my @profile = ();

    while ( my $r = shift @{$response->{"Response"}->{"Report"}} ) {
        if ( $r->{"Name"} eq "Line RateChange" ) {
            while (my $rec = shift @{$r->{Record}} ) {
                my %a = ();
                if ( $args{dateformat} ) {
                    foreach ( "SyncTimestamp", "BIPUpdateTime", "LineRateTimestamp" ) {
                        next unless $rec->{$_};
                        my $d = Time::Piece->strptime($rec->{$_}, "%d/%m/%Y %H:%M:%S");
                        $a{lc $_} = $d->strftime($args{dateformat});
                    }
                }
                foreach ( keys %$rec ) {
                    $a{lc $_} = $rec->{$_};
                }
                push @rate, \%a;
            }
        }
        elsif ( $r->{"Name"} eq "Service Profile" ) {
            while (my $rec = shift @{$r->{Record}} ) {
                my %a = ();
                if ( $args{dateformat} ) {
                    foreach ( "SyncTimestamp", "BIPUpdateTime", "LineRateTimestamp" ) {
                        next unless $rec->{$_};
                        my $d = Time::Piece->strptime($rec->{$_}, "%d/%m/%Y %H:%M:%S");
                        $rec->{lc $_} = $d->strftime($args{dateformat});
                    }
                }
                foreach (keys %$rec ) {
                    $a{lc $_} = $rec->{$_};
                }
                push @profile, \%a;
            }
        }
    }
    $line{"ratechange"} = \@rate;
    $line{"profile"} = \@profile;

    return %line;
}

=head2 order_eventlog_history

    $enta->order_eventlog_history( username => "myusername" );

Gets the provisioning history for a specified customer order.

Takes "username" as parameter.

Returns an array, each element of which details an order update.

=cut

sub order_eventlog_history { goto &getadslinstall; }

=head2 getadslinstall

    $enta->getadslinstall( username => "username", dateformat => "%d %b %Y" );

Get's the provisioning history for the specified customer

Returns an array, each element of which is a hash detailing an update as
follows:

date
name
value

=cut

sub getadslinstall {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ( 'username' ) );

    my $response = $self->make_request("GetAdslInstall", \%args);

    my $dateformat = "%Y-%m-%d";
    $dateformat = $args{dateformat} if $args{dateformat};

    my @history = ();
    while ( my $log = shift @{$response->{Response}->{OperationResponse}->{InstallReturns}->{InstallReturn}} ) {
        my %a = ();
        my $d = localtime($log->{DateReceived});
        $a{date} = $d->strftime($dateformat);
        $a{name} = "status";
        $a{value} = $log->{OrderType}.' '.$log->{LineItemSubstatus};
        if ( $log->{LineItemSubstatus} eq 'COMMITTED' ) {
            print "Adding ".$log->{CommitDate}." to ".$a{value}."\n";
            my $c = Time::Piece->strptime($log->{CommitDate}, "%d-%b-%Y");
            $a{value} .= ' for '.$c->strftime($dateformat);
        }

        push @history, \%a;
    }
    
    return @history;
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
    $self->_check_params(\%args, ( "service-id|telephone|ref|username" ));
    
    my $data = $self->serviceid(\%args);
    
    my $response = $self->make_request("AdslAccount", $data );

    my %adsl = ();
    foreach (keys %{$response->{Response}->{OperationResponse}} ) {
        if ( ref $response->{Response}->{OperationResponse}->{$_} eq 'HASH' ) {
            my $b = $_;
            foreach ( keys %{$response->{Response}->{OperationResponse}->{$b}} ) {
                $adsl{lc $b}{lc $_} = $response->{Response}->{OperationResponse}->{$b}->{$_};
            }
        }
        else {
            $adsl{lc $_} = $response->{Response}->{OperationResponse}->{$_};
        }
    }
    $adsl{service_details}->{live} = 'N';
    $adsl{service_details}->{live} = 'Y' if $adsl{adslaccount}->{status} eq 'Installed';

    $adsl{adslaccount}->{provisiondate} =~ /(.*) \+0\d00/;
    my $activation_date = Time::Piece->strptime($1, "%a, %d %b %Y %H:%M:%S");

    if ( $args{dateformat} ) {
        $adsl{service_details}->{activation_date} = $activation_date->strftime($args{dateformat});
    }
    else {
        $adsl{service_details}->{activation_date} = $activation_date->ymd;
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
    my ($self, %args) = @_;
    my @required = ( qw/title county telephone email crd 
            routed-ip username password linespeed topup care-level 
            billing-period contract-term initial-payment ongoing-payment
            payment-method totl max-interleaving/ );

    for (qw/ctitle cforename csurname cstreet ctown ccounty cpostcode
        ctelephone cemail/) {
        if ( $args{"customer-id"} eq 'New' ) {
            push @required, $_;
        }
        else {
            delete $args{$_} if $args{$_};
        }
    }

    $self->_check_params(\%args, @required);

    $args{"isdn"} = 'N';
    $entatype{"CreateADSLOrder"} = "ADSLMigrationOrder" if $args{mac};
    my $d = Time::Piece->strptime($args{"crd"}, "%F");
    $args{"crd"} = $d->dmy("/");

    my $data = $self->convert_input("CreateADSLOrder", \%args);

    my $response = $self->make_request("CreateADSLOrder", $data);

    return ( "order_id" => $response->{Response}->{OperationResponse}->{OurRef},
             "service_id" => $response->{Response}->{OperationResponse}->{OurRef},
             "payment_code" => $response->{Response}->{OperationResponse}->{TelephonePaymentCode} );
}

=head2 terms_and_conditions

    Returns the URI where the T&C for Entanet services is located.

=cut

sub terms_and_conditions {
    return "http://www.enta.net/downloads/entanet_tandc.pdf";
}

=head2 product_change

    Not implemented in Enta API Yet

=cut

sub product_change {
    return;
}

=head2 regrade

    Not Implemented in Enta API Yet

=cut

sub regrade {
    return;
}

=head2 usage_summary 

    $enta->usage_summary( "service-id" => "ADSL12345", "year" => '2009', "month" => '01' );

Returns a summary of usage in the given month

=cut 

sub usage_summary {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ("service-id|ref|username|telephone"));

    my $data = $self->serviceid(\%args);

    my $s = $args{year}."-".$args{month}."-1";
    my $start = Time::Piece->strptime($s, "%F");
    $args{"startday"} = $start->ymd;

    my $e = $args{year}."-".$args{month}."-".$start->month_last_day;
    my $end = Time::Piece->strptime($e, "%F");
    $args{"endday"} = $end->ymd;

    my @history = $self->usage_history_detail(%args);
    my $downstream = 0;
    my $upstream = 0;
    my $peakdownstream = 0;
    my $peakupstream = 0;

    while ( my $h = pop @history ) {
        $downstream += $h->{totaldown};
        $upstream += $h->{totalup};
        $peakdownstream += $h->{peakdown};
        $peakupstream += $h->{peakup};
    }

    return (
        "year" => $args{"year"},
        "month" => $args{"month"},
        "total_input_octets" => $downstream,
        "total_output_octets" => $upstream,
        "peak_input_octets" => $peakdownstream,
        "peak_output_octets" => $peakupstream
    );
}

sub usage_history {
    my ($self, %args) = @_;
    $self->_check_params(\%args, (qw/startdatetime enddatetime/));

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

    my $s = Time::Piece->strptime($response->{Response}->{OperationResponse}->{StartDateTime}, "%d %b %Y %H:%M:%S");
    my $e = Time::Piece->strptime($response->{Response}->{OperationResponse}->{EndDateTime}, "%d %b %Y %H:%M:%S");

    my %u = ();

    if ( $args{dateformat} ) {
        $u{"start_date_time"} = $s->strftime($args{dateformat});
        $u{"end_date_time"} = $e->strftime($args{dateformat});
    }
    else {
        $u{"start_date_time"} = $s->ymd.' '.$s->hms;
        $u{"end_date_time"} = $e->ymd.' '.$e->hms;
    }

    $u{peak_download} = $response->{Response}->{OperationResponse}->{PeakDownload};
    $u{peak_upload} = $response->{Response}->{OperationResponse}->{PeakUpload};
    $u{download} = $response->{Response}->{OperationResponse}->{Download};
    $u{upload} = $response->{Response}->{OperationResponse}->{Upload};

    return %u;
}

=head2 usage_history_detail

    $enta->usage_history_detail( "service-id" => "ADSL12345", 
        startday => '2009-12-01', endday => '2010-02-01',
        dateformat => "%a, %d %m %Y");
   
    $enta->usage_history_detail( "service-id" => "ADSL12345", 
        day => '2010-02-01' );

Returns usage details for each day in a period or each 10 minute period
in a day if called with day as the parameter.

Parameters:

    service-id : Service identifier (or ref, username or telephone)
    startday   : Start date in ISO format
    endday     : End data in ISO format
    day        : Date in ISO format
    dateformat : Format string per strftime. Defaults to ISO. (Optional)

Either the startday and endday parameters or the day parameter must be 
passed.

Returns an array, each element of which is a hash containing usage details
for either a day or a 10 minute interval.

Data returned per a day has the following keys:

    date        : Date formatted for presentation ( eg Mon, 22 Feb 2010 )
    totaldown   : Total number of bytes downloaded
    totalup     : Total number of bytes uploaded
    peakdown    : Bytes downloaded during peak period
    peakup      : Bytes uploaded during peak period

Data returned per 10 minute interval for a day:

    time    : Time at end of measured time interval
    down    : bytes downloaded during interval
    up      : bytes uploaded during interval
    
=cut

sub usage_history_detail {
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

    my $date_format = "%Y-%m-%d";
    $date_format = $args{dateformat} if $args{dateformat};

    my $response = $self->make_request("UsageHistoryDetail", $data);

    my @usage = ();
    if ( $args{"day"} ) {
        while (my $r = shift @{$response->{ResponseType}->{Detail}->{Usage}} ) {
            my %row = ();
            foreach ( keys %{$r} ) {
                my $key = lc $_;
                $row{$key} = $r->{$_};
            }
            push @usage, \%row;
        }
    }
    else {
        if ( ref $response->{ResponseType}->{Day} eq 'ARRAY' ) {
            while (my $r = shift @{$response->{ResponseType}->{Day}} ) {
                my %row = ();
                my $d = Time::Piece->strptime($r->{Date}, "%F");
                $row{'date'} = $d->strftime($date_format);
                $row{'totalup'} = $r->{Total}->{Up};
                $row{'totaldown'} = $r->{Total}->{Down};
                $row{'peakup'} = $r->{Peak}->{Up};
                $row{'peakdown'} = $r->{Peak}->{Down};

                push @usage, \%row;
            }
        }
        else {
            my %row = ();
            my $d = Time::Piece->strptime($response->{ResponseType}->{Day}->{Date}, "%F");
            $row{'date'} = $d->strftime($date_format);
            $row{'totalup'} = $response->{ResponseType}->{Day}->{Total}->{Up};
            $row{'totaldown'} = $response->{ResponseType}->{Day}->{Total}->{Down};
            $row{'peakup'} = $response->{ResponseType}->{Day}->{Peak}->{Up};
            $row{'peakdown'} = $response->{ResponseType}->{Day}->{Peak}->{Down};

            push @usage, \%row;
        }
    }
    return @usage;
}

=head2 allowance

    $enta->allowance( "service-id" => "ADSL12345" );

Returns details of the customers bandwidth usage allowance including
overall allowance and any overusage (topup or payg) allowances on the 
account.

=cut

sub allowance {
    my ($self, %args) = @_;
    $self->_check_params(\%args, ("service-id|telephone|ref|username") );
    my $data = undef;
    $args{'ref'} = $args{"service-id"} if $args{"service-id"};
    for (qw/telephone ref username/) {
        $data->{$_} = $args{$_} if $args{$_};
    }
    my $response = $self->make_request("ADSLTopup", $data );

    return %{$response->{Response}->{OperationResponse}};
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
    $self->_check_params(\%args, ("service-id|telephone|ref|username", "days"));
  
    # Enta ConnectionHistory is keyed from Username only so we need to 
    # obtain the username if we don't have it.

    my $data = undef;
    if ( ! $args{"username"} ) {
        my %adsl = $self->adslaccount(%args);
        $data = { "username" => $adsl{adslaccount}->{username} };
    }
    else {
        $data = $self->serviceid(\%args);
    }

    $data->{days} = $args{days} if $args{days};

    my $date_format = "%Y-%m-%d %H:%M:%S";
    $date_format = $args{dateformat} if $args{dateformat};

    my $response = $self->make_request("ConnectionHistory", $data);
    
    my @history = ();

    if ( ref $response->{Response}->{OperationResponse}->{Connection} eq 'ARRAY' ) {
        while ( my $h = pop @{$response->{Response}->{OperationResponse}->{Connection}} ) {
            my %a = ();
            my $start = Time::Piece->strptime($h->{"StartDateTime"}, "%d %b %Y %H:%M:%S");
            my $end = Time::Piece->strptime($h->{"EndDateTime"}, "%d %b %Y %H:%M:%S");
            $a{"start_time"} = $start->strftime($date_format);
            $a{"stop_time"} = $end->strftime($date_format);
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

            $a{"termination_reason"} = "Not Available";

            push @history, \%a;
        }
    }
    else {
        my %a = ();
        my $start = Time::Piece->strptime($response->{Response}->{OperationResponse}->{Connection}->{"StartDateTime"}, "%d %b %Y %H:%M:%S");
        my $end = Time::Piece->strptime($response->{Response}->{OperationResponse}->{Connection}->{"EndDateTime"}, "%d %b %Y %H:%M:%S");
        $a{"start_time"} = $start->strftime($date_format);
        $a{"stop_time"} = $end->strftime($date_format);
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

        $a{"termination_reason"} = "Not Available";

        push @history, \%a;
    }
    return @history;
}

=head2 case_search

=cut

sub case_search {
    my ( $self, %args ) = @_;
    $self->_check_params(\%args, qw/ref|username|service-id/);

    my $data = $self->serviceid(\%args);

    my $response = $self->make_request("GetNotes", $data);

    my @c = ();
    my $date_format = "%Y-%m-%d %H:%M:%S";
    $date_format = $args{dateformat} if $args{dateformat};
    if ( ref $response->{Response}->{OperationResponse}->{Notes}->{Note} eq 'ARRAY' ) {
        for my $c ( @{$response->{Response}->{OperationResponse}->{Notes}->{Note}} ) {
            my %n = ();
    
            $c->{TimeStamp} =~ /(.*) \+0\d00/;
            my $t = Time::Piece->strptime($1, "%a, %d %b %Y %H:%M:%S");
            $n{description} = $c->{Text};
            $n{engineer} = 'Enta Staff';
            $n{engineer} = $c->{User} if $c->{User} =~ /\@/;
            $n{logged} = $t->strftime($date_format);
            push @c, \%n;
        }
    }
    else {
        my %n = ();
        my $c = $response->{Response}->{OperationResponse}->{Notes}->{Note};
        $c->{TimeStamp} =~ /(.*) \+0\d00/;
        my $t = Time::Piece->strptime($1, "%a, %d %b %Y %H:%M:%S");
        $n{description} = $c->{Text};
        $n{engineer} = 'Enta Staff';
        $n{engineer} = $c->{User} if $c->{User} =~ /\@/;
        $n{logged} = $t->strftime($date_format);
        push @c, \%n;
    }
    return @c;
}

=head2 first_crd

    $enta->first_crd();

Returns the first date an order may be placed for.

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
    return $adsl{adslaccount}->{ourref};
}

sub debug_dump {
    use Data::Dumper;
    warn Dumper \$_[1];
}

1;
